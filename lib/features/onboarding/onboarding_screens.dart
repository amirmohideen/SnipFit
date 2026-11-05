import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../config/legal_versions.dart';
import '../../core/analytics/analytics.dart';
import '../../core/analytics/analytics_events.dart';
import '../../core/storage/local_store.dart';
import '../../core/storage/media_store.dart';
import '../../design/illustrations/figure_art.dart';
import '../../design/illustrations/snip_animation.dart';
import '../../design/tokens.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/common.dart';
import '../../design/widgets/step_scaffold.dart';
import '../../l10n/l10n.dart';
import '../consent/consent_repository.dart';
import '../modes/app_mode.dart';

/// Logs a funnel step once when the screen first builds.
mixin _TracksStep<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  String get step;

  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).track(AnalyticsEvents.onboardingStepViewed, {AnalyticsProps.step: step});
  }
}

Future<void> finishOnboarding(WidgetRef ref) => ref.read(localStoreProvider).setBool(Keys.onboardingDone, true);

String _locale(BuildContext context) => Localizations.localeOf(context).toLanguageTag();

// --------------------------------------------------------------------- hook

class HookScreen extends ConsumerStatefulWidget {
  const HookScreen({this.replay = false, super.key});

  final bool replay;

  @override
  ConsumerState<HookScreen> createState() => _HookScreenState();
}

class _HookScreenState extends ConsumerState<HookScreen> with _TracksStep {
  @override
  String get step => 'hook';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.s3, Space.s3, Space.s3, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.card + 8),
                  child: Semantics(label: l10n.hookAnimationLabel, image: true, child: const HookAnimation()),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.s3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(l10n.hookHeadline, style: Theme.of(context).textTheme.displaySmall),
                  ),
                  const SizedBox(height: Space.s3),
                  PrimaryButton(
                    label: l10n.getStarted,
                    onPressed: () => widget.replay ? context.go('/how-it-works') : context.go('/age'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------- age

class AgeScreen extends ConsumerStatefulWidget {
  const AgeScreen({super.key});

  @override
  ConsumerState<AgeScreen> createState() => _AgeScreenState();
}

class _AgeScreenState extends ConsumerState<AgeScreen> with _TracksStep {
  @override
  String get step => 'age';

  int? _year;

  Future<void> _pickYear() async {
    final now = DateTime.now().year;
    final years = [for (var y = now; y >= now - 100; y--) y];
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: ListView.builder(
          itemCount: years.length,
          itemBuilder: (context, i) => ListTile(
            title: Text('${years[i]}', textAlign: TextAlign.center),
            selected: years[i] == _year,
            onTap: () => Navigator.pop(context, years[i]),
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _year = picked);
  }

  Future<void> _continue() async {
    final ok = await ref.read(ageProvider.notifier).submitBirthYear(_year!, locale: _locale(context));
    if (!mounted) return;
    if (ok) {
      await ref.read(analyticsProvider).track(AnalyticsEvents.ageConfirmed, {
        AnalyticsProps.isAdult: ref.read(ageProvider).isAdult,
      });
      if (mounted) context.go('/terms');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final age = ref.watch(ageProvider);
    if (age.blocked) {
      return StepScaffold(
        body: StepHeader(title: l10n.ageBlockedTitle, subtitle: l10n.ageBlockedBody),
        actions: const [],
      );
    }
    return StepScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StepHeader(title: l10n.ageTitle, subtitle: l10n.ageSubtitle),
          const SizedBox(height: Space.s4),
          Semantics(
            button: true,
            label: _year == null ? l10n.selectBirthYear : l10n.birthYearSelected(_year!),
            excludeSemantics: true,
            child: OutlinedButton(
              onPressed: _pickYear,
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(64)),
              child: Text(_year == null ? l10n.selectBirthYear : '$_year'),
            ),
          ),
        ],
      ),
      actions: [PrimaryButton(label: l10n.continueLabel, onPressed: _year == null ? null : _continue)],
    );
  }
}

// -------------------------------------------------------------------- terms

class TermsScreen extends ConsumerStatefulWidget {
  const TermsScreen({super.key});

  @override
  ConsumerState<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends ConsumerState<TermsScreen> with _TracksStep {
  @override
  String get step => 'terms';

  bool _agreed = false;
  bool _saving = false;

  Future<void> _continue() async {
    setState(() => _saving = true);
    await ref.read(consentProvider.notifier).set(ConsentType.terms, accepted: true, locale: _locale(context));
    await ref.read(analyticsProvider).track(AnalyticsEvents.termsAccepted);
    if (!mounted) return;
    final analyticsPrompt = ref.read(analyticsConsentProvider.notifier).needsPrompt;
    context.go(analyticsPrompt ? '/privacy-choices' : '/mode');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    Widget bullet(IconData icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24),
          const SizedBox(width: Space.s2),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
    return StepScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StepHeader(title: l10n.termsTitle),
          const SizedBox(height: Space.s3),
          bullet(Icons.phone_iphone, l10n.termsBullet1),
          bullet(Icons.shield_outlined, l10n.termsBullet2),
          bullet(Icons.people_outline, l10n.termsBullet3),
          const SizedBox(height: Space.s2),
          Wrap(
            children: [
              LinkButton(label: l10n.termsOfUse, onPressed: () => context.push('/legal/${LegalDoc.terms.slug}')),
              LinkButton(label: l10n.privacyPolicy, onPressed: () => context.push('/legal/${LegalDoc.privacy.slug}')),
            ],
          ),
          const SizedBox(height: Space.s1),
          ConsentCheckbox(
            key: const Key('terms-checkbox'),
            value: _agreed,
            onChanged: (v) => setState(() => _agreed = v),
            label: l10n.termsCheckbox,
          ),
        ],
      ),
      actions: [
        PrimaryButton(
          key: const Key('terms-continue'),
          label: l10n.continueLabel,
          busy: _saving,
          onPressed: _agreed ? _continue : null,
        ),
      ],
    );
  }
}

// -------------------------------------------------------- analytics consent

class PrivacyChoicesScreen extends ConsumerStatefulWidget {
  const PrivacyChoicesScreen({super.key});

  @override
  ConsumerState<PrivacyChoicesScreen> createState() => _PrivacyChoicesScreenState();
}

class _PrivacyChoicesScreenState extends ConsumerState<PrivacyChoicesScreen> {
  Future<void> _choose(bool allow) async {
    await ref.read(analyticsConsentProvider.notifier).set(allow ? AnalyticsConsent.granted : AnalyticsConsent.denied);
    if (!mounted) return;
    await ref.read(consentProvider.notifier).set(ConsentType.analytics, accepted: allow, locale: _locale(context));
    if (mounted) context.go('/mode');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return StepScaffold(
      onSkip: () => _choose(false),
      skipLabel: l10n.skip,
      body: StepHeader(title: l10n.analyticsTitle, subtitle: l10n.analyticsBody),
      actions: [
        PrimaryButton(label: l10n.allow, onPressed: () => _choose(true)),
        SecondaryButton(label: l10n.notNow, onPressed: () => _choose(false)),
      ],
    );
  }
}

// --------------------------------------------------------------- mode picker

class ModePickerScreen extends ConsumerStatefulWidget {
  const ModePickerScreen({super.key});

  @override
  ConsumerState<ModePickerScreen> createState() => _ModePickerScreenState();
}

class _ModePickerScreenState extends ConsumerState<ModePickerScreen> with _TracksStep {
  @override
  String get step => 'mode';

  Future<void> _select(AppMode mode) async {
    await ref.read(modeProvider.notifier).select(mode);
    await ref.read(analyticsProvider).track(AnalyticsEvents.modeSelected, {AnalyticsProps.mode: mode.name});
    if (mounted) context.go('/camera-intro');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final modes = ref.watch(availableModesProvider);
    String title(AppMode m) => switch (m) {
      AppMode.women => l10n.modeWomen,
      AppMode.hijab => l10n.modeHijab,
      AppMode.men => l10n.modeMen,
    };
    String subtitle(AppMode m) => switch (m) {
      AppMode.women => l10n.modeWomenSubtitle,
      AppMode.hijab => l10n.modeHijabSubtitle,
      AppMode.men => l10n.modeMenSubtitle,
    };
    FigureKind kind(AppMode m) => switch (m) {
      AppMode.women => FigureKind.women,
      AppMode.hijab => FigureKind.hijab,
      AppMode.men => FigureKind.men,
    };
    return StepScaffold(
      onSkip: () async {
        await finishOnboarding(ref);
        if (context.mounted) context.go('/');
      },
      skipLabel: l10n.skip,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StepHeader(title: l10n.modeTitle),
          const SizedBox(height: Space.s3),
          for (final m in modes) ...[
            Semantics(
              button: true,
              label: '${title(m)}. ${subtitle(m)}',
              excludeSemantics: true,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _select(m),
                  child: SizedBox(
                    height: 168,
                    child: Row(
                      children: [
                        SizedBox(width: 128, child: ModeArt(kind: kind(m))),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(Space.s2),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title(m), style: Theme.of(context).textTheme.titleLarge),
                                const SizedBox(height: Space.xs),
                                Text(subtitle(m), style: Theme.of(context).textTheme.bodyMedium),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.s2),
          ],
        ],
      ),
      actions: const [],
    );
  }
}

// ---------------------------------------------------------- camera explainer

class CameraIntroScreen extends ConsumerStatefulWidget {
  const CameraIntroScreen({super.key});

  @override
  ConsumerState<CameraIntroScreen> createState() => _CameraIntroScreenState();
}

class _CameraIntroScreenState extends ConsumerState<CameraIntroScreen> with _TracksStep {
  @override
  String get step => 'camera';

  bool _denied = false;

  Future<void> _continue() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isGranted || status.isLimited) {
      final biometricOk = ref.read(consentProvider)[ConsentType.biometric] ?? false;
      context.go(biometricOk ? '/capture?guided=1' : '/biometric?next=${Uri.encodeComponent('/capture?guided=1')}');
    } else {
      setState(() => _denied = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Future<void> skip() async {
      await finishOnboarding(ref);
      if (context.mounted) context.go('/');
    }
    if (_denied) {
      return StepScaffold(
        onSkip: skip,
        skipLabel: l10n.skip,
        body: StepHeader(title: l10n.cameraDeniedTitle, subtitle: l10n.cameraDeniedBody),
        actions: [
          PrimaryButton(label: l10n.openSettings, onPressed: openAppSettings),
          SecondaryButton(
            label: l10n.uploadInstead,
            onPressed: () {
              final biometricOk = ref.read(consentProvider)[ConsentType.biometric] ?? false;
              context.go(biometricOk ? '/capture?guided=1' : '/biometric?next=${Uri.encodeComponent('/capture?guided=1')}');
            },
          ),
        ],
      );
    }
    return StepScaffold(
      onSkip: skip,
      skipLabel: l10n.skip,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.phone_iphone, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: Space.s2),
          StepHeader(title: l10n.cameraIntroTitle, subtitle: l10n.cameraIntroBody),
        ],
      ),
      // The button says "Continue", never "Allow"; the system prompt follows.
      actions: [PrimaryButton(label: l10n.continueLabel, onPressed: _continue)],
    );
  }
}

// ---------------------------------------------------------------- biometric

/// Shown before the first face processing, for everyone (not only Illinois).
class BiometricConsentScreen extends ConsumerStatefulWidget {
  const BiometricConsentScreen({this.next, super.key});

  final String? next;

  @override
  ConsumerState<BiometricConsentScreen> createState() => _BiometricConsentScreenState();
}

class _BiometricConsentScreenState extends ConsumerState<BiometricConsentScreen> with _TracksStep {
  @override
  String get step => 'biometric';

  bool _agreed = false;

  Future<void> _continue() async {
    await ref.read(consentProvider.notifier).set(ConsentType.biometric, accepted: true, locale: _locale(context));
    if (mounted) context.go(widget.next ?? '/capture');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return StepScaffold(
      onSkip: () async {
        await finishOnboarding(ref);
        if (context.mounted) context.go('/');
      },
      skipLabel: l10n.notNow,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StepHeader(title: l10n.biometricTitle),
          const SizedBox(height: Space.s2),
          Text(l10n.biometricBody1, style: theme.textTheme.bodyLarge),
          const SizedBox(height: Space.s1),
          Text(l10n.biometricBody2, style: theme.textTheme.bodyLarge),
          const SizedBox(height: Space.s1),
          Text(l10n.biometricBody3, style: theme.textTheme.bodyLarge),
          LinkButton(label: l10n.readBiometricNotice, onPressed: () => context.push('/legal/${LegalDoc.biometric.slug}')),
          const SizedBox(height: Space.s1),
          ConsentCheckbox(value: _agreed, onChanged: (v) => setState(() => _agreed = v), label: l10n.biometricCheckbox),
        ],
      ),
      actions: [PrimaryButton(label: l10n.continueLabel, onPressed: _agreed ? _continue : null)],
    );
  }
}

/// "How it works" replay from Settings: the practice overlay on the latest
/// window, or a guided first capture if there is none yet.
class HowItWorksRedirect extends ConsumerWidget {
  const HowItWorksRedirect({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final windows = ref.watch(windowsProvider);
    final latest = windows.value;
    if (latest != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        context.go(latest.isEmpty ? '/capture?guided=1' : '/live/${latest.first.id}?practice=1');
      });
    }
    return const Scaffold(body: Center(child: SnipSpinner()));
  }
}
