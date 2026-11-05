import 'dart:io' show Platform;

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
import '../../core/storage/local_store.dart';
import '../../core/storage/media_store.dart';
import '../../design/widgets/common.dart';
import '../../l10n/l10n.dart';
import '../consent/consent_repository.dart';
import '../paywall/entitlements.dart';
import '../paywall/purchases_service.dart';
import 'preferences.dart';

final appVersionLabelProvider = Provider<String>((ref) => ref.watch(appVersionProvider));

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  String _locale(BuildContext context) => Localizations.localeOf(context).toLanguageTag();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final backend = ref.watch(backendStatusProvider);
    final user = ref.watch(currentUserProvider).value;
    final ent = ref.watch(entitlementsProvider);
    final consents = ref.watch(consentProvider);
    final analyticsConsent = ref.watch(analyticsConsentProvider);
    final optInRegion = ref.read(analyticsConsentProvider.notifier).optInRegion;
    final config = ref.watch(appConfigProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    String docTitle(LegalDoc d) => switch (d) {
      LegalDoc.terms => l10n.termsOfUse,
      LegalDoc.privacy => l10n.privacyPolicy,
      LegalDoc.biometric => l10n.biometricNotice,
      LegalDoc.aiDisclosure => l10n.aiDisclosure,
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        children: [
          // ------------------------------------------------------- account
          SectionHeader(l10n.account),
          if (!backend.firebaseReady)
            ListTile(title: Text(l10n.accountsUnavailable), subtitle: Text(l10n.accountsUnavailableBody))
          else ...[
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(
                user == null
                    ? l10n.notSignedIn
                    : user.hasApple
                    ? l10n.signedInApple
                    : user.hasGoogle
                    ? l10n.signedInGoogle
                    : l10n.anonymousAccount,
              ),
              subtitle: (user == null || user.isAnonymous) ? Text(l10n.signInWhy) : null,
            ),
            if (user == null || user.isAnonymous) ...[
              ListTile(
                leading: const Icon(Icons.apple),
                title: Text(l10n.signInApple),
                onTap: () => _link(context, ref, apple: true),
              ),
              ListTile(
                leading: const Icon(Icons.g_mobiledata),
                title: Text(l10n.signInGoogle),
                onTap: () => _link(context, ref, apple: false),
              ),
            ] else
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(l10n.signOut),
                onTap: () => ref.read(authServiceProvider).signOut(),
              ),
          ],

          // -------------------------------------------------- subscription
          SectionHeader(l10n.subscription),
          ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: Text(ent.isPro ? l10n.proActive : l10n.freePlan),
            subtitle: Text(l10n.creditBalance(ent.aiTryOnsAvailable)),
            trailing: ent.isPro ? null : TextButton(onPressed: () => context.push('/paywall?trigger=settings'), child: Text(l10n.getPro)),
          ),
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: Text(l10n.manageSubscription),
            onTap: () async {
              final url = await ref.read(purchasesServiceProvider).managementUrl() ??
                  storeSubscriptionsPage(androidPackage: config.androidPackage);
              await launchUrl(url, mode: LaunchMode.externalApplication);
            },
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: Text(l10n.restorePurchases),
            onTap: () async {
              await ref.read(analyticsProvider).track(AnalyticsEvents.restoreTapped);
              final user = await ref.read(authServiceProvider).ensureSignedIn();
              if (user != null) await ref.read(purchasesServiceProvider).identify(user.uid);
              final pro = await ref.read(purchasesServiceProvider).restore();
              if (context.mounted) showSnack(context, pro ? l10n.restoreSuccess : l10n.restoreNothing);
            },
          ),

          // ------------------------------------------------------- privacy
          SectionHeader(l10n.privacy),
          SwitchListTile(
            secondary: const Icon(Icons.insights_outlined),
            title: Text(l10n.usageAnalytics),
            subtitle: Text(l10n.usageAnalyticsBody),
            value: analyticsAllowed(analyticsConsent, optInRegion: optInRegion),
            onChanged: (v) async {
              await ref.read(analyticsConsentProvider.notifier).set(v ? AnalyticsConsent.granted : AnalyticsConsent.denied);
              if (context.mounted) {
                await ref.read(consentProvider.notifier).set(ConsentType.analytics, accepted: v, locale: _locale(context));
              }
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.auto_awesome_outlined),
            title: Text(l10n.aiConsentSetting),
            subtitle: Text(l10n.aiConsentSettingBody),
            value: consents[ConsentType.ai] ?? false,
            onChanged: (v) async {
              if (v) {
                await context.push('/ai/consent');
              } else {
                await ref.read(consentProvider.notifier).set(ConsentType.ai, accepted: false, locale: _locale(context));
                if (context.mounted) showSnack(context, l10n.aiConsentWithdrawn);
              }
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.face_retouching_natural_outlined),
            title: Text(l10n.faceConsentSetting),
            subtitle: Text(l10n.faceConsentSettingBody),
            value: consents[ConsentType.biometric] ?? false,
            onChanged: (v) async {
              if (v) {
                await context.push('/biometric?next=${Uri.encodeComponent('/settings')}');
              } else {
                await ref.read(consentProvider.notifier).set(ConsentType.biometric, accepted: false, locale: _locale(context));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: Text(l10n.deleteLocalData),
            subtitle: Text(l10n.deleteLocalDataBody),
            onTap: () async {
              if (await _confirm(context, l10n.deleteLocalData, l10n.deleteLocalDataConfirm)) {
                await ref.read(mediaStoreProvider).deleteAll();
                ref.read(mediaRevisionProvider.notifier).bump();
                if (context.mounted) showSnack(context, l10n.deleted);
              }
            },
          ),
          if (backend.firebaseReady && user != null)
            ListTile(
              leading: Icon(Icons.person_remove_outlined, color: theme.colorScheme.error),
              title: Text(l10n.deleteAccount, style: TextStyle(color: theme.colorScheme.error)),
              subtitle: Text(l10n.deleteAccountBody),
              onTap: () => _deleteAccount(context, ref),
            ),

          // ---------------------------------------------------------- help
          SectionHeader(l10n.help),
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: Text(l10n.howItWorks),
            onTap: () => context.go('/welcome?replay=1'),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(l10n.contactSupport),
            subtitle: Text(config.supportEmail),
            onTap: () => launchUrl(config.supportMail),
          ),

          // --------------------------------------------------------- legal
          SectionHeader(l10n.legal),
          for (final d in LegalDoc.values)
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(docTitle(d)),
              onTap: () => context.push('/legal/${d.slug}'),
            ),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(l10n.licenses),
            onTap: () => showLicensePage(context: context, applicationName: 'Snipfit'),
          ),

          // ---------------------------------------------------- appearance
          SectionHeader(l10n.appearance),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text(l10n.themeSystem)),
                ButtonSegment(value: ThemeMode.light, label: Text(l10n.themeLight)),
                ButtonSegment(value: ThemeMode.dark, label: Text(l10n.themeDark)),
              ],
              selected: {themeMode},
              onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(l10n.language),
            subtitle: Text(locale == null ? l10n.languageSystem : _languageName(locale.languageCode)),
            onTap: () => _pickLanguage(context, ref),
          ),
          ListTile(title: Text(l10n.versionLabel(ref.watch(appVersionLabelProvider))), dense: true),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static String _languageName(String code) => switch (code) {
    'en' => 'English',
    'ar' => 'العربية',
    'tr' => 'Türkçe',
    'ms' => 'Bahasa Melayu',
    'id' => 'Bahasa Indonesia',
    _ => code,
  };

  Future<void> _pickLanguage(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final codes = ['', ...supportedLocales.map((l) => l.languageCode)];
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in codes)
              ListTile(title: Text(c.isEmpty ? l10n.languageSystem : _languageName(c)), onTap: () => Navigator.pop(context, c)),
          ],
        ),
      ),
    );
    if (picked != null) await ref.read(localeProvider.notifier).set(picked.isEmpty ? null : Locale(picked));
  }

  Future<void> _link(BuildContext context, WidgetRef ref, {required bool apple}) async {
    final l10n = context.l10n;
    final auth = ref.read(authServiceProvider);
    final outcome = apple ? await auth.linkWithApple() : await auth.linkWithGoogle();
    if (!context.mounted) return;
    final user = auth.currentUser;
    if (user != null && (outcome == LinkOutcome.linked || outcome == LinkOutcome.switchedAccount)) {
      await ref.read(purchasesServiceProvider).identify(user.uid);
      await ref.read(consentProvider.notifier).sync();
    }
    if (!context.mounted) return;
    showSnack(context, switch (outcome) {
      LinkOutcome.linked => l10n.signInLinked,
      LinkOutcome.switchedAccount => l10n.signInSwitched,
      LinkOutcome.cancelled => l10n.signInCancelled,
      LinkOutcome.failed => l10n.signInFailed,
    });
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    if (!await _confirm(context, l10n.deleteAccount, l10n.deleteAccountConfirm)) return;
    try {
      await ref.read(authServiceProvider).deleteAccount();
      await ref.read(mediaStoreProvider).deleteAll();
      await ref.read(localStoreProvider).clearAll();
      ref.invalidate(consentProvider);
      ref.invalidate(ageProvider);
      ref.read(mediaRevisionProvider.notifier).bump();
      if (context.mounted) {
        showSnack(context, l10n.accountDeleted);
        context.go('/welcome');
      }
    } on Object {
      if (context.mounted) showSnack(context, l10n.deleteAccountFailed(ref.read(appConfigProvider).accountDeletionPage.toString()));
    }
  }

  Future<bool> _confirm(BuildContext context, String title, String body) async {
    final l10n = context.l10n;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
              TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete)),
            ],
          ),
        ) ??
        false;
  }
}

/// Kept for platform-specific copy (e.g. "App Store" vs "Google Play").
bool get isApplePlatform => Platform.isIOS || Platform.isMacOS;
