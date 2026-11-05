import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import '../storage/local_store.dart';
import 'analytics_events.dart';

/// Product analytics. Events carry no images or personal details; see
/// [AnalyticsPropertyFilter].
abstract class Analytics {
  Future<void> track(String event, [Map<String, Object?>? props]);
  Future<void> screen(String name);
  Future<void> setEnabled(bool enabled);
  Future<void> identify(String userId);
  Future<void> reset();
  Future<Object?> featureFlag(String key);
}

class NoopAnalytics implements Analytics {
  const NoopAnalytics();

  @override
  Future<void> track(String event, [Map<String, Object?>? props]) async {
    if (kDebugMode) {
      debugPrint('[analytics] $event ${AnalyticsPropertyFilter.clean(props)}');
    }
  }

  @override
  Future<void> screen(String name) async {}

  @override
  Future<void> setEnabled(bool enabled) async {}

  @override
  Future<void> identify(String userId) async {}

  @override
  Future<void> reset() async {}

  @override
  Future<Object?> featureFlag(String key) async => null;
}

/// PostHog-backed analytics with session replay and screen capture off, so no
/// camera frame or photo can ever be recorded.
class PostHogAnalytics implements Analytics {
  PostHogAnalytics._();

  static Future<PostHogAnalytics> start({
    required String token,
    required String host,
    required bool enabled,
  }) async {
    final config = PostHogConfig(token)
      ..host = host
      ..sessionReplay = false
      ..captureApplicationLifecycleEvents = true
      ..personProfiles = PostHogPersonProfiles.identifiedOnly
      ..surveys = false
      ..optOut = !enabled
      ..debug = kDebugMode;
    await Posthog().setup(config);
    return PostHogAnalytics._();
  }

  final _posthog = Posthog();

  @override
  Future<void> track(String event, [Map<String, Object?>? props]) =>
      _posthog.capture(
        eventName: event,
        properties: AnalyticsPropertyFilter.clean(props),
      );

  @override
  Future<void> screen(String name) => _posthog.screen(screenName: name);

  @override
  Future<void> setEnabled(bool enabled) =>
      enabled ? _posthog.optIn() : _posthog.optOut();

  @override
  Future<void> identify(String userId) => _posthog.identify(userId: userId);

  @override
  Future<void> reset() => _posthog.reset();

  @override
  Future<Object?> featureFlag(String key) => _posthog.getFeatureFlag(key);
}

enum AnalyticsConsent { unset, granted, denied }

/// EU, EEA, UK and Switzerland: non-essential analytics need opt-in consent.
const _optInRegions = {
  'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE', 'GR', //
  'HU', 'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'NL', 'PL', 'PT', 'RO', 'SK', //
  'SI', 'ES', 'SE', 'IS', 'LI', 'NO', 'GB', 'CH',
};

/// True when the device region requires opt-in before analytics. An unknown
/// region is treated as requiring opt-in.
bool regionRequiresOptIn([String? countryCode]) {
  final code =
      countryCode ??
      PlatformDispatcher.instance.locales
          .map((l) => l.countryCode)
          .firstWhere((c) => c != null && c.isNotEmpty, orElse: () => null);
  if (code == null) return true;
  return _optInRegions.contains(code.toUpperCase());
}

/// Whether analytics may run, given the stored choice and the region.
bool analyticsAllowed(AnalyticsConsent consent, {required bool optInRegion}) =>
    optInRegion
    ? consent == AnalyticsConsent.granted
    : consent != AnalyticsConsent.denied;

class AnalyticsConsentController extends Notifier<AnalyticsConsent> {
  @override
  AnalyticsConsent build() {
    final raw = ref.read(localStoreProvider).getString(Keys.analyticsConsent);
    return AnalyticsConsent.values.firstWhere(
      (c) => c.name == raw,
      orElse: () => AnalyticsConsent.unset,
    );
  }

  bool get optInRegion => regionRequiresOptIn();

  bool get needsPrompt => optInRegion && state == AnalyticsConsent.unset;

  Future<void> set(AnalyticsConsent consent) async {
    state = consent;
    await ref
        .read(localStoreProvider)
        .setString(Keys.analyticsConsent, consent.name);
    await ref
        .read(analyticsProvider)
        .setEnabled(analyticsAllowed(consent, optInRegion: optInRegion));
  }
}

final analyticsConsentProvider =
    NotifierProvider<AnalyticsConsentController, AnalyticsConsent>(
      AnalyticsConsentController.new,
    );

final analyticsProvider = Provider<Analytics>((ref) => const NoopAnalytics());
