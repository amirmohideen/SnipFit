import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Build flavor. Each flavor has its own bundle ID, Firebase project and
/// RevenueCat sandbox so test data never mixes with production.
enum Flavor { dev, prod }

/// Static configuration for one flavor.
///
/// Values come from `--dart-define-from-file=config/<flavor>.json`. Everything
/// here is safe to ship inside the app: RevenueCat public SDK keys, the PostHog
/// project token and store identifiers are designed to be public. No AI or
/// cloud secret ever belongs here; those live in Cloud Functions secrets.
@immutable
class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.webDomain,
    required this.supportEmail,
    required this.revenueCatAppleKey,
    required this.revenueCatGoogleKey,
    required this.postHogToken,
    required this.postHogHost,
    required this.facebookAppId,
    required this.tiktokClientKey,
    required this.snapClientId,
    required this.appStoreId,
    required this.androidPackage,
    required this.googleServerClientId,
    required this.appStorePageWomen,
    required this.appStorePageHijab,
    required this.appStorePageMen,
    required this.playListingWomen,
    required this.playListingHijab,
    required this.playListingMen,
  });

  factory AppConfig.fromEnvironment(Flavor flavor) => AppConfig(
    flavor: flavor,
    webDomain: const String.fromEnvironment(
      'SNIPFIT_WEB_DOMAIN',
      defaultValue: 'snipfit.app',
    ),
    supportEmail: const String.fromEnvironment(
      'SNIPFIT_SUPPORT_EMAIL',
      defaultValue: 'support@snipfit.app',
    ),
    revenueCatAppleKey: const String.fromEnvironment('REVENUECAT_APPLE_KEY'),
    revenueCatGoogleKey: const String.fromEnvironment('REVENUECAT_GOOGLE_KEY'),
    postHogToken: const String.fromEnvironment('POSTHOG_TOKEN'),
    postHogHost: const String.fromEnvironment(
      'POSTHOG_HOST',
      defaultValue: 'https://eu.i.posthog.com',
    ),
    facebookAppId: const String.fromEnvironment('FACEBOOK_APP_ID'),
    tiktokClientKey: const String.fromEnvironment('TIKTOK_CLIENT_KEY'),
    snapClientId: const String.fromEnvironment('SNAP_CLIENT_ID'),
    appStoreId: const String.fromEnvironment('APP_STORE_ID'),
    androidPackage: const String.fromEnvironment(
      'ANDROID_PACKAGE',
      defaultValue: 'com.snipfit.app',
    ),
    googleServerClientId: const String.fromEnvironment(
      'GOOGLE_SERVER_CLIENT_ID',
    ),
    appStorePageWomen: const String.fromEnvironment('APP_STORE_PPID_WOMEN'),
    appStorePageHijab: const String.fromEnvironment('APP_STORE_PPID_HIJAB'),
    appStorePageMen: const String.fromEnvironment('APP_STORE_PPID_MEN'),
    playListingWomen: const String.fromEnvironment('PLAY_LISTING_WOMEN'),
    playListingHijab: const String.fromEnvironment('PLAY_LISTING_HIJAB'),
    playListingMen: const String.fromEnvironment('PLAY_LISTING_MEN'),
  );

  final Flavor flavor;

  /// Your own domain: hosts legal pages, invite links and the
  /// apple-app-site-association / assetlinks.json files.
  final String webDomain;
  final String supportEmail;
  final String revenueCatAppleKey;
  final String revenueCatGoogleKey;
  final String postHogToken;

  /// EU or US cloud. Chosen deliberately and named in the Privacy Policy.
  final String postHogHost;

  /// Required by Meta's Stories sharing (`source_application`).
  final String facebookAppId;
  final String tiktokClientKey;
  final String snapClientId;
  final String appStoreId;
  final String androidPackage;
  final String googleServerClientId;

  /// App Store custom product page IDs (`ppid`) per mode.
  final String appStorePageWomen;
  final String appStorePageHijab;
  final String appStorePageMen;

  /// Google Play custom store listing IDs (`listing`) per mode.
  final String playListingWomen;
  final String playListingHijab;
  final String playListingMen;

  bool get isDev => flavor == Flavor.dev;
  String get appName => isDev ? 'Snipfit Dev' : 'Snipfit';
  Uri get webBase => Uri.https(webDomain);
  Uri get accountDeletionPage => Uri.https(webDomain, '/delete-account');
  Uri get supportMail => Uri(scheme: 'mailto', path: supportEmail);
  bool get hasRevenueCat =>
      revenueCatAppleKey.isNotEmpty || revenueCatGoogleKey.isNotEmpty;
  bool get hasPostHog => postHogToken.isNotEmpty;
}

/// Overridden in bootstrap with the running flavor's config.
final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment(Flavor.dev));
