import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'core/analytics/analytics.dart';
import 'core/backend/auth_service.dart';
import 'core/backend/backend.dart';
import 'core/crash/crash_reporter.dart';
import 'core/flags/remote_flags.dart';
import 'core/notifications/notifications.dart';
import 'core/storage/local_store.dart';
import 'core/storage/media_store.dart';
import 'features/consent/consent_repository.dart';
import 'features/paywall/purchases_service.dart';
import 'features/share/export_service.dart';

/// Starts the app for a flavor. Every backend is optional: without Firebase,
/// RevenueCat or PostHog configured, the free features run fully offline.
Future<void> bootstrap(Flavor flavor, {required FirebaseOptions Function() firebaseOptions}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment(flavor);
  final store = await LocalStore.open();
  final media = await MediaStore.open();
  unawaited(ExportService.clearShareDir());
  final info = await PackageInfo.fromPlatform();

  var firebaseReady = false;
  try {
    await Firebase.initializeApp(options: firebaseOptions());
    firebaseReady = true;
  } on Object catch (e) {
    debugPrint('Firebase not configured, running local-only: $e');
  }

  final storedConsent = AnalyticsConsent.values.firstWhere(
    (c) => c.name == store.getString(Keys.analyticsConsent),
    orElse: () => AnalyticsConsent.unset,
  );
  final analyticsOn = analyticsAllowed(storedConsent, optInRegion: regionRequiresOptIn());

  CrashReporter crash = const DebugCrashReporter();
  if (firebaseReady) {
    crash = FirebaseCrashReporter(FirebaseCrashlytics.instance);
    await crash.setEnabled(analyticsOn);
  }
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    crash.recordError(details.exception, details.stack, fatal: true);
    previousOnError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    crash.recordError(error, stack, fatal: true);
    return true;
  };

  Analytics analytics = const NoopAnalytics();
  if (config.hasPostHog) {
    try {
      analytics = await PostHogAnalytics.start(token: config.postHogToken, host: config.postHogHost, enabled: analyticsOn);
    } on Object catch (e) {
      debugPrint('PostHog unavailable: $e');
    }
  }

  RemoteFlagsSource flags = const StaticRemoteFlagsSource();
  AuthService auth = const UnavailableAuthService();
  Notifications notifications = const NoopNotifications();
  if (firebaseReady) {
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode ? const AndroidDebugProvider() : const AndroidPlayIntegrityProvider(),
        providerApple: kDebugMode ? const AppleDebugProvider() : const AppleAppAttestWithDeviceCheckFallbackProvider(),
      );
      flags = await FirebaseRemoteFlagsSource.start();
    } on Object catch (e) {
      debugPrint('App Check / Remote Config unavailable: $e');
    }
    auth = FirebaseAuthService(googleServerClientId: config.googleServerClientId);
    notifications = FirebaseNotifications();
  }

  PurchasesService purchases = const UnavailablePurchasesService();
  final rcKey = Platform.isIOS ? config.revenueCatAppleKey : config.revenueCatGoogleKey;
  if (rcKey.isNotEmpty) {
    try {
      purchases = await RevenueCatPurchasesService.start(apiKey: rcKey);
    } on Object catch (e) {
      debugPrint('RevenueCat unavailable: $e');
    }
  }

  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(config),
      localStoreProvider.overrideWithValue(store),
      mediaStoreProvider.overrideWithValue(media),
      appVersionProvider.overrideWithValue('${info.version} (${info.buildNumber})'),
      backendStatusProvider.overrideWithValue(BackendStatus(firebaseReady: firebaseReady)),
      crashReporterProvider.overrideWithValue(crash),
      analyticsProvider.overrideWithValue(analytics),
      remoteFlagsSourceProvider.overrideWithValue(flags),
      authServiceProvider.overrideWithValue(auth),
      notificationsProvider.overrideWithValue(notifications),
      purchasesServiceProvider.overrideWithValue(purchases),
    ],
  );

  if (firebaseReady) unawaited(_afterStart(container));
  runApp(UncontrolledProviderScope(container: container, child: const SnipfitApp()));
}

/// Anonymous sign-in, then link RevenueCat to the same ID (so the webhook
/// credits the right ledger) and upload any consent records made offline.
Future<void> _afterStart(ProviderContainer c) async {
  try {
    final auth = c.read(authServiceProvider);
    auth.userChanges.listen((user) async {
      if (user == null) return;
      try {
        await c.read(purchasesServiceProvider).identify(user.uid);
      } on Object catch (e) {
        debugPrint('RevenueCat identify failed: $e');
      }
      await c.read(consentProvider.notifier).sync();
    });
    await auth.ensureSignedIn();
  } on Object catch (e) {
    debugPrint('post-start tasks skipped: $e');
  }
}
