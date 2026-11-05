import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Operational switches from Firebase Remote Config. Defaults keep the app
/// fully usable offline and before Firebase is configured.
@immutable
class RemoteFlags {
  const RemoteFlags({
    this.menModeEnabled = false,
    this.aiTryOnEnabled = true,
    this.liveArEnabled = false,
    this.softPaywallEnabled = true,
    this.revealVideoEnabled = true,
    this.shareKitsEnabled = true,
    this.paywallOfferingId = '',
    this.creditsOfferingId = 'credits',
    this.trialExperimentEnabled = false,
  });

  /// Men's mode ships after launch; the mode card stays hidden until then.
  final bool menModeEnabled;

  /// Kill switch for the paid AI try-on (the server has its own switch too).
  final bool aiTryOnEnabled;

  /// Live AR stays off, and off the paywall, until it ships and works.
  final bool liveArEnabled;
  final bool softPaywallEnabled;
  final bool revealVideoEnabled;
  final bool shareKitsEnabled;

  /// RevenueCat offering for the paywall; empty means "current offering".
  /// Changing it runs a price test without an app update.
  final String paywallOfferingId;
  final String creditsOfferingId;

  /// Allows the PostHog `paywall_trial` experiment to show a free trial.
  final bool trialExperimentEnabled;

  static const keys = (
    menMode: 'men_mode_enabled',
    aiTryOn: 'ai_tryon_enabled',
    liveAr: 'live_ar_enabled',
    softPaywall: 'soft_paywall_enabled',
    revealVideo: 'reveal_video_enabled',
    shareKits: 'share_kits_enabled',
    paywallOffering: 'paywall_offering_id',
    creditsOffering: 'credits_offering_id',
    trialExperiment: 'trial_experiment_enabled',
  );

  static Map<String, Object> get defaults {
    const d = RemoteFlags();
    return {
      keys.menMode: d.menModeEnabled,
      keys.aiTryOn: d.aiTryOnEnabled,
      keys.liveAr: d.liveArEnabled,
      keys.softPaywall: d.softPaywallEnabled,
      keys.revealVideo: d.revealVideoEnabled,
      keys.shareKits: d.shareKitsEnabled,
      keys.paywallOffering: d.paywallOfferingId,
      keys.creditsOffering: d.creditsOfferingId,
      keys.trialExperiment: d.trialExperimentEnabled,
    };
  }
}

abstract class RemoteFlagsSource {
  RemoteFlags get current;
  Stream<RemoteFlags> get updates;
}

class StaticRemoteFlagsSource implements RemoteFlagsSource {
  const StaticRemoteFlagsSource([this.current = const RemoteFlags()]);

  @override
  final RemoteFlags current;

  @override
  Stream<RemoteFlags> get updates => const Stream.empty();
}

class FirebaseRemoteFlagsSource implements RemoteFlagsSource {
  FirebaseRemoteFlagsSource._(this._rc);

  final FirebaseRemoteConfig _rc;
  final _controller = StreamController<RemoteFlags>.broadcast();

  static Future<FirebaseRemoteFlagsSource> start() async {
    final rc = FirebaseRemoteConfig.instance;
    await rc.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 8),
        minimumFetchInterval: kDebugMode
            ? const Duration(minutes: 1)
            : const Duration(hours: 1),
      ),
    );
    await rc.setDefaults(RemoteFlags.defaults);
    final source = FirebaseRemoteFlagsSource._(rc);
    // Fetch in the background; never block startup on the network.
    unawaited(
      rc.fetchAndActivate().then((_) => source._emit()).catchError((_) {}),
    );
    rc.onConfigUpdated.listen(
      (_) async {
        await rc.activate();
        source._emit();
      },
      onError: (_) {},
    );
    return source;
  }

  void _emit() => _controller.add(current);

  @override
  RemoteFlags get current => RemoteFlags(
    menModeEnabled: _rc.getBool(RemoteFlags.keys.menMode),
    aiTryOnEnabled: _rc.getBool(RemoteFlags.keys.aiTryOn),
    liveArEnabled: _rc.getBool(RemoteFlags.keys.liveAr),
    softPaywallEnabled: _rc.getBool(RemoteFlags.keys.softPaywall),
    revealVideoEnabled: _rc.getBool(RemoteFlags.keys.revealVideo),
    shareKitsEnabled: _rc.getBool(RemoteFlags.keys.shareKits),
    paywallOfferingId: _rc.getString(RemoteFlags.keys.paywallOffering),
    creditsOfferingId: _rc.getString(RemoteFlags.keys.creditsOffering),
    trialExperimentEnabled: _rc.getBool(RemoteFlags.keys.trialExperiment),
  );

  @override
  Stream<RemoteFlags> get updates => _controller.stream;
}

final remoteFlagsSourceProvider = Provider<RemoteFlagsSource>(
  (ref) => const StaticRemoteFlagsSource(),
);

class RemoteFlagsController extends Notifier<RemoteFlags> {
  @override
  RemoteFlags build() {
    final source = ref.watch(remoteFlagsSourceProvider);
    final sub = source.updates.listen((flags) => state = flags);
    ref.onDispose(sub.cancel);
    return source.current;
  }
}

final remoteFlagsProvider = NotifierProvider<RemoteFlagsController, RemoteFlags>(
  RemoteFlagsController.new,
);
