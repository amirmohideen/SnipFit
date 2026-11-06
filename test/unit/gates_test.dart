import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snipfit/config/legal_versions.dart';
import 'package:snipfit/core/analytics/analytics.dart';
import 'package:snipfit/core/storage/local_store.dart';
import 'package:snipfit/features/ai_tryon/ai_gate.dart';
import 'package:snipfit/features/consent/consent_repository.dart';
import 'package:snipfit/features/paywall/entitlements.dart';
import 'package:snipfit/routing/router.dart';

Future<ProviderContainer> container([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final store = await LocalStore.open();
  final c = ProviderContainer(overrides: [localStoreProvider.overrideWithValue(store)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('AI gate', () {
    AiGate gate({
      bool feature = true,
      bool backend = true,
      bool adult = true,
      bool consent = true,
      Entitlements ent = const Entitlements(credits: 3),
      bool reference = true,
    }) => evaluateAiGate(
      featureEnabled: feature,
      backendReady: backend,
      isAdult: adult,
      aiConsent: consent,
      entitlements: ent,
      hasReferencePhoto: reference,
    );

    test('ready only when every requirement is met', () {
      expect(gate(), AiGate.ready);
    });

    test('checks requirements in the order a person resolves them', () {
      expect(gate(feature: false), AiGate.unavailable);
      expect(gate(backend: false), AiGate.unavailable);
      expect(gate(adult: false, consent: false), AiGate.notAdult);
      expect(gate(ent: const Entitlements(credits: 3, suspended: true)), AiGate.suspended);
      expect(gate(consent: false, ent: const Entitlements()), AiGate.needsConsent);
      expect(gate(ent: const Entitlements()), AiGate.needsCredits);
      expect(gate(reference: false), AiGate.needsReference);
    });

    test('Pro allowance counts as available try-ons', () {
      expect(gate(ent: const Entitlements(isPro: true, allowanceLeft: 30)), AiGate.ready);
    });
  });

  group('onboarding redirects', () {
    const passed = AgeStatus(passed: true, isAdult: true);
    String? go(String path, {AgeStatus age = passed, bool terms = true, bool bio = true, bool done = true}) =>
        onboardingRedirect(uri: Uri.parse(path), age: age, termsAccepted: terms, biometricAccepted: bio, onboardingDone: done);

    test('legal documents are always reachable', () {
      expect(go('/legal/terms', age: const AgeStatus(passed: false, isAdult: false), terms: false, done: false), isNull);
    });

    test('age and terms cannot be skipped', () {
      expect(go('/', age: const AgeStatus(passed: false, isAdult: false), done: false), '/welcome');
      expect(go('/capture', age: const AgeStatus(passed: false, isAdult: false)), '/age');
      expect(go('/', terms: false), '/terms');
      expect(go('/settings', terms: false), '/terms');
    });

    test('blocked under-13 users stay on the age screen', () {
      final blocked = AgeStatus(passed: false, isAdult: false, blockedUntil: DateTime.now().add(const Duration(hours: 5)));
      expect(go('/', age: blocked), '/age');
      expect(go('/age', age: blocked), isNull);
    });

    test('face processing requires the biometric consent', () {
      expect(go('/capture?guided=1', bio: false), '/biometric?next=${Uri.encodeComponent('/capture?guided=1')}');
      expect(go('/capture'), isNull);
    });

    test('a changed Terms version asks again', () {
      expect(go('/live/abc', terms: false), '/terms');
    });

    test('unfinished onboarding resumes at the mode picker', () {
      expect(go('/', done: false), '/mode');
    });
  });

  group('age gate', () {
    test('blocks under 13 for a day and never stores the birth year', () async {
      final c = await container();
      // The block lasts 24 hours from the real clock, so use today's date.
      final birthYear = DateTime.now().year - 10;
      final ok = await c.read(ageProvider.notifier).submitBirthYear(birthYear, locale: 'en');
      expect(ok, isFalse);
      expect(c.read(ageProvider).blocked, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().any((k) => prefs.get(k).toString().contains('$birthYear')), isFalse);
    });

    test('uses the youngest possible age, so a 17-year-old is never an adult', () async {
      final c = await container();
      final now = DateTime(2026, 11, 5);
      // Born in 2008: 17 or 18 depending on the birthday, so not an adult yet.
      await c.read(ageProvider.notifier).submitBirthYear(2008, locale: 'en', now: now);
      expect(c.read(ageProvider).passed, isTrue);
      expect(c.read(ageProvider).isAdult, isFalse);
      await c.read(ageProvider.notifier).submitBirthYear(2007, locale: 'en', now: now);
      expect(c.read(ageProvider).isAdult, isTrue);
    });

    test('13 is allowed (born 2012 can only be 13 or 14 at the end of 2026)', () async {
      final c = await container();
      expect(await c.read(ageProvider.notifier).submitBirthYear(2012, locale: 'en', now: DateTime(2026, 12, 31)), isTrue);
      expect(await c.read(ageProvider.notifier).submitBirthYear(2013, locale: 'en', now: DateTime(2026, 12, 31)), isFalse);
    });
  });

  group('consent records', () {
    test('record version and timestamp, and re-ask when the version changes', () async {
      final c = await container();
      final repo = c.read(consentRepositoryProvider);
      expect(repo.hasCurrent(ConsentType.terms), isFalse);
      await repo.record(ConsentType.terms, accepted: true, locale: 'en');
      expect(repo.hasCurrent(ConsentType.terms), isTrue);
      final saved = repo.latest(ConsentType.terms)!;
      expect(saved['version'], ConsentVersions.terms);
      expect(DateTime.tryParse(saved['at']! as String), isNotNull);
      expect(saved['appVersion'], isNotNull);

      // Simulate an older accepted version.
      final store = c.read(localStoreProvider);
      await store.setJson('consent.terms', {...saved, 'version': 'old'});
      expect(repo.hasCurrent(ConsentType.terms), isFalse);
      expect(repo.needsReconsent(ConsentType.terms), isTrue);
    });

    test('withdrawal turns the consent off and is queued for sync', () async {
      final c = await container();
      final notifier = c.read(consentProvider.notifier);
      await notifier.set(ConsentType.ai, accepted: true, locale: 'en');
      expect(c.read(consentProvider)[ConsentType.ai], isTrue);
      await notifier.set(ConsentType.ai, accepted: false, locale: 'en');
      expect(c.read(consentProvider)[ConsentType.ai], isFalse);
      final pending = c.read(localStoreProvider).getJsonList(Keys.consentPending);
      expect(pending.map((r) => r['accepted']), [true, false]);
    });
  });

  group('analytics consent', () {
    test('EU/UK users need opt-in; others can opt out', () {
      expect(regionRequiresOptIn('DE'), isTrue);
      expect(regionRequiresOptIn('GB'), isTrue);
      expect(regionRequiresOptIn('US'), isFalse);
      expect(regionRequiresOptIn('MY'), isFalse);
      expect(analyticsAllowed(AnalyticsConsent.unset, optInRegion: true), isFalse);
      expect(analyticsAllowed(AnalyticsConsent.granted, optInRegion: true), isTrue);
      expect(analyticsAllowed(AnalyticsConsent.unset, optInRegion: false), isTrue);
      expect(analyticsAllowed(AnalyticsConsent.denied, optInRegion: false), isFalse);
    });
  });
}
