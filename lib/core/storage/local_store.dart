import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Small typed wrapper around [SharedPreferences] for app state that must
/// survive restarts. Never store photos, landmarks or masks here.
class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<LocalStore> open() async =>
      LocalStore(await SharedPreferences.getInstance());

  bool getBool(String key, {bool fallback = false}) =>
      _prefs.getBool(key) ?? fallback;
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  int? getInt(String key) => _prefs.getInt(key);
  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);

  Future<void> remove(String key) => _prefs.remove(key);

  Map<String, Object?>? getJson(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as Map).cast<String, Object?>();
    } on FormatException {
      return null;
    }
  }

  Future<void> setJson(String key, Map<String, Object?> value) =>
      _prefs.setString(key, jsonEncode(value));

  List<Map<String, Object?>> getJsonList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => (e as Map).cast<String, Object?>())
          .toList();
    } on FormatException {
      return const [];
    }
  }

  Future<void> setJsonList(String key, List<Map<String, Object?>> value) =>
      _prefs.setString(key, jsonEncode(value));

  /// A random ID for this install. Not tied to the person or the hardware;
  /// regenerated on reinstall. Used for invite codes and device rate limits.
  String get installId {
    final existing = _prefs.getString(Keys.installId);
    if (existing != null) return existing;
    final id = const Uuid().v4();
    _prefs.setString(Keys.installId, id);
    return id;
  }

  /// Removes everything (used by "Delete all my data").
  Future<void> clearAll() => _prefs.clear();
}

/// All preference keys in one place.
abstract final class Keys {
  static const installId = 'install.id';
  static const onboardingDone = 'onboarding.done';
  static const ageIsAdult = 'age.isAdult';
  static const agePassed = 'age.passed';
  static const ageBlockedAt = 'age.blockedAt';
  static const consentPrefix = 'consent.';
  static const consentPending = 'consent.pending';
  static const analyticsConsent = 'analytics.consent';
  static const mode = 'mode.current';
  static const themeMode = 'settings.themeMode';
  static const localeOverride = 'settings.locale';
  static const softPaywallShown = 'paywall.softShown';
  static const firstCompareDone = 'milestone.firstCompare';
  static const notificationsAsked = 'notifications.asked';
  static const reviewAskedAt = 'review.askedAt';
  static const freshSelfieTipDismissed = 'tip.freshSelfie';
  static const practiceDone = 'onboarding.practiceDone';
  static const pendingInviteMode = 'invite.pendingMode';
  static const aiReferencePhoto = 'ai.referencePhoto';
}

final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('LocalStore is provided in bootstrap'),
);
