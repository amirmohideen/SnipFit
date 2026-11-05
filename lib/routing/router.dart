import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/analytics/analytics.dart';
import '../core/analytics/analytics_events.dart';
import '../core/storage/local_store.dart';
import '../features/ai_tryon/ai_screens.dart';
import '../features/capture/capture_screen.dart';
import '../features/compare/compare_screen.dart';
import '../features/consent/consent_repository.dart';
import '../features/cutout/refine/refine_screen.dart';
import '../features/home/home_screen.dart';
import '../features/invite/invite_links.dart';
import '../features/legal/legal_screen.dart';
import '../features/live_window/live_window_screen.dart';
import '../features/modes/app_mode.dart';
import '../features/onboarding/onboarding_screens.dart';
import '../features/paywall/paywall_screen.dart';
import '../features/settings/settings_screen.dart';

/// Re-runs redirects when the age gate or consents change.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(ageProvider, (_, _) => notifyListeners());
    ref.listen(consentProvider, (_, _) => notifyListeners());
  }
}

/// Pure redirect logic, unit-testable.
///
/// - Legal documents are always reachable (no account, no consent needed).
/// - Age and Terms are the only non-skippable steps.
/// - Face processing (capture) requires the biometric consent.
String? onboardingRedirect({
  required Uri uri,
  required AgeStatus age,
  required bool termsAccepted,
  required bool biometricAccepted,
  required bool onboardingDone,
}) {
  final loc = uri.path;
  if (loc.startsWith('/legal')) return null;
  if (age.blocked) return loc == '/age' ? null : '/age';
  if (!age.passed) {
    if (loc == '/welcome' || loc == '/age') return null;
    return onboardingDone ? '/age' : '/welcome';
  }
  if (!termsAccepted) return loc == '/terms' ? null : '/terms';
  if (loc == '/age' || loc == '/terms') return onboardingDone ? '/' : '/mode';
  if (loc == '/welcome' && onboardingDone && uri.queryParameters['replay'] != '1') return '/';
  if (loc == '/' && !onboardingDone) return '/mode';
  if (loc == '/capture' && !biometricAccepted) {
    return '/biometric?next=${Uri.encodeComponent(uri.toString())}';
  }
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final consents = ref.read(consentProvider);
      return onboardingRedirect(
        uri: state.uri,
        age: ref.read(ageProvider),
        termsAccepted: consents[ConsentType.terms] ?? false,
        biometricAccepted: consents[ConsentType.biometric] ?? false,
        onboardingDone: ref.read(localStoreProvider).getBool(Keys.onboardingDone),
      );
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/welcome', builder: (_, s) => HookScreen(replay: s.uri.queryParameters['replay'] == '1')),
      GoRoute(path: '/age', builder: (_, _) => const AgeScreen()),
      GoRoute(path: '/terms', builder: (_, _) => const TermsScreen()),
      GoRoute(path: '/privacy-choices', builder: (_, _) => const PrivacyChoicesScreen()),
      GoRoute(path: '/mode', builder: (_, _) => const ModePickerScreen()),
      GoRoute(path: '/camera-intro', builder: (_, _) => const CameraIntroScreen()),
      GoRoute(path: '/biometric', builder: (_, s) => BiometricConsentScreen(next: s.uri.queryParameters['next'])),
      GoRoute(path: '/how-it-works', builder: (_, _) => const HowItWorksRedirect()),
      GoRoute(path: '/capture', builder: (_, s) => CaptureScreen(guided: s.uri.queryParameters['guided'] == '1')),
      GoRoute(path: '/refine', builder: (_, s) => RefineScreen(guided: s.uri.queryParameters['guided'] == '1')),
      GoRoute(
        path: '/live/:id',
        builder: (_, s) => LiveWindowScreen(windowId: s.pathParameters['id']!, practice: s.uri.queryParameters['practice'] == '1'),
      ),
      GoRoute(
        path: '/compare/:id',
        builder: (_, s) => CompareScreen(windowId: s.pathParameters['id']!, firstRun: s.uri.queryParameters['first'] == '1'),
      ),
      GoRoute(
        path: '/paywall',
        pageBuilder: (_, s) => MaterialPage(
          fullscreenDialog: true,
          child: PaywallScreen(trigger: s.uri.queryParameters['trigger'] ?? 'unknown'),
        ),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/legal/:slug', builder: (_, s) => LegalScreen(slug: s.pathParameters['slug']!)),
      GoRoute(path: '/ai', builder: (_, s) => AiHubScreen(windowId: s.uri.queryParameters['window'])),
      GoRoute(path: '/ai/consent', builder: (_, _) => const AiConsentScreen()),
      GoRoute(path: '/ai/reference', builder: (_, _) => const ReferencePhotoScreen()),
      GoRoute(
        path: '/ai/garment',
        builder: (_, s) => GarmentScreen(gallery: s.uri.queryParameters['gallery'] == '1', windowId: s.uri.queryParameters['window']),
      ),
      GoRoute(
        path: '/ai/progress/:id',
        builder: (_, s) => TryOnProgressScreen(requestId: s.pathParameters['id']!, windowId: s.uri.queryParameters['window']),
      ),
      GoRoute(
        path: '/ai/result/:id',
        builder: (_, s) => TryOnResultScreen(requestId: s.pathParameters['id']!, windowId: s.uri.queryParameters['window']),
      ),
      // Invite links (universal links / App Links) land here.
      GoRoute(path: '/i/:code', builder: (_, s) => InviteLanding(uri: s.uri)),
    ],
  );
});

class InviteLanding extends ConsumerStatefulWidget {
  const InviteLanding({required this.uri, super.key});

  final Uri uri;

  @override
  ConsumerState<InviteLanding> createState() => _InviteLandingState();
}

class _InviteLandingState extends ConsumerState<InviteLanding> {
  @override
  void initState() {
    super.initState();
    final parsed = InviteLinks.parse(widget.uri);
    final mode = parsed?.mode;
    ref.read(analyticsProvider).track(AnalyticsEvents.inviteOpened, {AnalyticsProps.mode: mode?.name ?? 'none'});
    if (mode != null && ref.read(availableModesProvider).contains(mode)) {
      ref.read(modeProvider.notifier).select(mode);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/');
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}
