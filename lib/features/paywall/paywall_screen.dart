import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../config/legal_versions.dart';
import '../../core/analytics/analytics.dart';
import '../../core/analytics/analytics_events.dart';
import '../../core/backend/auth_service.dart';
import '../../core/backend/backend.dart';
import '../../core/flags/remote_flags.dart';
import '../../design/illustrations/figure_art.dart';
import '../../design/tokens.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/common.dart';
import '../../l10n/l10n.dart';
import '../modes/app_mode.dart';
import 'entitlements.dart';
import 'purchases_service.dart';

final paywallOfferProvider = FutureProvider.autoDispose<PaywallOffer?>((ref) async {
  final purchases = ref.watch(purchasesServiceProvider);
  if (!purchases.available) return null;
  final flags = ref.watch(remoteFlagsProvider);
  return purchases.loadOffer(offeringId: flags.paywallOfferingId, creditsOfferingId: flags.creditsOfferingId);
});

/// Whether the PostHog experiment assigned this person to the free-trial
/// variant. Default is a direct purchase.
final trialVariantProvider = FutureProvider.autoDispose<bool>((ref) async {
  if (!ref.watch(remoteFlagsProvider).trialExperimentEnabled) return false;
  final value = await ref.watch(analyticsProvider).featureFlag('paywall_trial');
  return value == 'trial';
});

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({required this.trigger, super.key});

  /// Where the paywall was opened from (analytics only).
  final String trigger;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  PlanKind _selected = PlanKind.yearly;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).track(AnalyticsEvents.paywallViewed, {AnalyticsProps.trigger: widget.trigger});
  }

  void _close() => context.canPop() ? context.pop() : context.go('/');

  Future<bool> _ensureAccount() async {
    if (!ref.read(backendStatusProvider).firebaseReady) return false;
    final user = await ref.read(authServiceProvider).ensureSignedIn();
    if (user == null) return false;
    await ref.read(purchasesServiceProvider).identify(user.uid);
    return true;
  }

  Future<void> _buy(Plan plan) async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    final analytics = ref.read(analyticsProvider);
    try {
      if (!await _ensureAccount()) {
        if (mounted) showSnack(context, l10n.purchasesUnavailable);
        return;
      }
      await analytics.track(AnalyticsEvents.purchaseStarted, {AnalyticsProps.product: plan.productId});
      final outcome = await ref.read(purchasesServiceProvider).purchase(plan);
      if (!mounted) return;
      switch (outcome) {
        case PurchaseOutcome.success:
          await analytics.track(AnalyticsEvents.purchaseCompleted, {AnalyticsProps.product: plan.productId});
          if (!mounted) return;
          showSnack(context, plan.kind == PlanKind.credits ? l10n.creditsOnTheirWay : l10n.welcomeToPro);
          _close();
        case PurchaseOutcome.pending:
          showSnack(context, l10n.purchasePending);
        case PurchaseOutcome.cancelled:
          break;
        case PurchaseOutcome.failed:
        case PurchaseOutcome.unavailable:
          showSnack(context, l10n.purchaseFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final l10n = context.l10n;
    await ref.read(analyticsProvider).track(AnalyticsEvents.restoreTapped);
    setState(() => _busy = true);
    try {
      await _ensureAccount();
      final pro = await ref.read(purchasesServiceProvider).restore();
      if (mounted) showSnack(context, pro ? l10n.restoreSuccess : l10n.restoreNothing);
    } on Object {
      if (mounted) showSnack(context, l10n.purchaseFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final offer = ref.watch(paywallOfferProvider);
    final trial = ref.watch(trialVariantProvider).value ?? false;
    final mode = ref.watch(modeProvider);
    final liveAr = ref.watch(remoteFlagsProvider.select((f) => f.liveArEnabled));
    final isPro = ref.watch(entitlementsProvider).isPro;
    final config = ref.watch(appConfigProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 1. Close button, visible from the first frame, no delay.
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton(
                key: const Key('paywall-close'),
                tooltip: l10n.close,
                icon: const Icon(Icons.close),
                onPressed: _close,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: Space.s3),
                children: [
                  _Hero(mode: mode),
                  const SizedBox(height: Space.s2),
                  Text(l10n.paywallTitle, style: theme.textTheme.displaySmall),
                  const SizedBox(height: Space.s2),
                  _Benefit(icon: Icons.auto_awesome_outlined, text: l10n.benefitAiTryOns),
                  _Benefit(icon: Icons.hide_image_outlined, text: l10n.benefitNoWatermark),
                  _Benefit(icon: Icons.palette_outlined, text: l10n.benefitBestColors),
                  if (liveAr) _Benefit(icon: Icons.view_in_ar_outlined, text: l10n.benefitLiveAr),
                  const SizedBox(height: Space.s1),
                  Text(l10n.freeForever, style: theme.textTheme.bodySmall),
                  const SizedBox(height: Space.s2),
                  offer.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(Space.s4),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, _) => _Unavailable(text: l10n.storeLoadFailed),
                    data: (o) {
                      if (o == null || o.isEmpty) return _Unavailable(text: l10n.purchasesUnavailable);
                      return _Plans(
                        offer: o,
                        selected: _selected,
                        trial: trial,
                        isPro: isPro,
                        busy: _busy,
                        onSelect: (k) => setState(() => _selected = k),
                        onBuy: _buy,
                      );
                    },
                  ),
                  const SizedBox(height: Space.s1),
                  // 7. Terms, Privacy and Restore.
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      LinkButton(
                        label: l10n.termsOfUse,
                        onPressed: () => context.push('/legal/${LegalDoc.terms.slug}'),
                      ),
                      LinkButton(
                        label: l10n.privacyPolicy,
                        onPressed: () => context.push('/legal/${LegalDoc.privacy.slug}'),
                      ),
                      LinkButton(label: l10n.restorePurchases, onPressed: _busy ? () {} : _restore),
                      LinkButton(
                        label: l10n.manageSubscription,
                        onPressed: () async {
                          final url = await ref.read(purchasesServiceProvider).managementUrl() ??
                              storeSubscriptionsPage(androidPackage: config.androidPackage);
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.s3),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.mode});

  final AppMode mode;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final kind = switch (mode) {
      AppMode.hijab => FigureKind.hijab,
      AppMode.men => FigureKind.men,
      AppMode.women => FigureKind.women,
    };
    Widget panel(String label, Color? fabric) => Expanded(
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.card),
              child: CustomPaint(
                size: Size.infinite,
                painter: FigurePainter(kind: kind, fabric: fabric, cutProgress: 0),
              ),
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
    return Semantics(
      label: l10n.paywallHeroLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: 210,
        child: Row(
          children: [
            panel(l10n.before, null),
            const SizedBox(width: Space.s1),
            panel(l10n.aiLook, const Color(0xFF6E8B74)),
          ],
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 24),
        const SizedBox(width: Space.s2),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
      ],
    ),
  );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.s3),
    child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
  );
}

class _Plans extends StatelessWidget {
  const _Plans({
    required this.offer,
    required this.selected,
    required this.trial,
    required this.isPro,
    required this.busy,
    required this.onSelect,
    required this.onBuy,
  });

  final PaywallOffer offer;
  final PlanKind selected;
  final bool trial;
  final bool isPro;
  final bool busy;
  final ValueChanged<PlanKind> onSelect;
  final ValueChanged<Plan> onBuy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final plan = selected == PlanKind.yearly ? (offer.yearly ?? offer.monthly) : (offer.monthly ?? offer.yearly);
    final intro = trial ? plan?.intro : null;
    final hasTrial = intro != null && intro.isFree;

    String periodName(PlanPeriod p) => p == PlanPeriod.year ? l10n.periodYear : l10n.periodMonth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 4. Plan selector, yearly preselected with its monthly equivalent.
        if (offer.yearly != null)
          _PlanTile(
            selected: selected == PlanKind.yearly,
            title: l10n.planYearly,
            price: l10n.pricePerYear(offer.yearly!.priceString),
            detail: offer.yearly!.monthlyEquivalentString == null
                ? null
                : l10n.monthlyEquivalent(offer.yearly!.monthlyEquivalentString!),
            badge: l10n.bestValue,
            onTap: () => onSelect(PlanKind.yearly),
          ),
        if (offer.monthly != null) ...[
          const SizedBox(height: Space.s1),
          _PlanTile(
            selected: selected == PlanKind.monthly,
            title: l10n.planMonthly,
            price: l10n.pricePerMonth(offer.monthly!.priceString),
            onTap: () => onSelect(PlanKind.monthly),
          ),
        ],
        const SizedBox(height: Space.s2),
        if (plan != null && !isPro) ...[
          // 5. The button names the action and the price.
          PrimaryButton(
            key: const Key('paywall-buy'),
            busy: busy,
            label: hasTrial
                ? l10n.startFreeTrial(_durationText(l10n, intro.units, intro.unit))
                : l10n.subscribeFor(
                    plan.period == PlanPeriod.year ? l10n.pricePerYear(plan.priceString) : l10n.pricePerMonth(plan.priceString),
                  ),
            onPressed: () => onBuy(plan),
          ),
          const SizedBox(height: Space.s1),
          // 6. Full disclosure directly under the button, in readable type.
          Text(
            hasTrial
                ? l10n.trialDisclosure(
                    _durationText(l10n, intro.units, intro.unit),
                    plan.period == PlanPeriod.year ? l10n.planYearly : l10n.planMonthly,
                    plan.priceString,
                    periodName(plan.period),
                  )
                : l10n.subscriptionDisclosure(
                    plan.period == PlanPeriod.year ? l10n.planYearly : l10n.planMonthly,
                    periodName(plan.period),
                    plan.priceString,
                  ),
            key: const Key('paywall-disclosure'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(l10n.howToCancel, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
        ],
        if (isPro) Text(l10n.youArePro, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
        if (offer.credits != null) ...[
          const SizedBox(height: Space.s3),
          const Divider(),
          const SizedBox(height: Space.s2),
          Text(l10n.creditsTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(l10n.creditsBody, style: theme.textTheme.bodySmall),
          const SizedBox(height: Space.s1),
          SecondaryButton(
            label: l10n.buyCredits(offer.credits!.priceString),
            onPressed: busy ? null : () => onBuy(offer.credits!),
          ),
        ],
      ],
    );
  }

  static String _durationText(AppLocalizations l10n, int units, PlanPeriod unit) => switch (unit) {
    PlanPeriod.year => l10n.durationYears(units),
    PlanPeriod.month => l10n.durationMonths(units),
    PlanPeriod.none => l10n.durationDays(units),
  };
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.selected, required this.title, required this.price, required this.onTap, this.detail, this.badge});

  final bool selected;
  final String title;
  final String price;
  final String? detail;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.card),
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          padding: const EdgeInsets.all(Space.s2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(
              color: selected ? theme.colorScheme.onSurface : theme.colorScheme.outline,
              width: selected ? 2 : 1,
            ),
          ),
          // Stacked rather than one long row, so large system text sizes and
          // long localized prices never overflow.
          child: Row(
            children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off),
              const SizedBox(width: Space.s2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: Space.s1,
                      runSpacing: Space.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        if (badge != null) PillBadge(label: badge!, emphasized: true),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(price, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                    if (detail != null) Text(detail!, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
