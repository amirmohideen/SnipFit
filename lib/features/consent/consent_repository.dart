import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/legal_versions.dart';
import '../../core/backend/auth_service.dart';
import '../../core/backend/backend.dart';
import '../../core/storage/local_store.dart';

enum ConsentType {
  /// Terms of Use + Privacy Policy clickwrap.
  terms,

  /// Biometric notice: face processing on the device.
  biometric,

  /// Sending photos to the server and Google's AI for a paid try-on.
  ai,

  /// The neutral age screen (records only the 18+ flag, never the year).
  age,

  /// Non-essential analytics (EU/UK opt-in).
  analytics;

  String get currentVersion => switch (this) {
    ConsentType.terms => ConsentVersions.terms,
    ConsentType.biometric => ConsentVersions.biometric,
    ConsentType.ai => ConsentVersions.ai,
    ConsentType.age => 'v1',
    ConsentType.analytics => 'v1',
  };
}

/// One acceptance or withdrawal, as logged locally and in Firestore.
@immutable
class ConsentRecord {
  const ConsentRecord({
    required this.type,
    required this.version,
    required this.accepted,
    required this.at,
    required this.appVersion,
    required this.locale,
    this.extra = const {},
  });

  final ConsentType type;
  final String version;
  final bool accepted;
  final DateTime at;
  final String appVersion;
  final String locale;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
    'type': type.name,
    'version': version,
    'accepted': accepted,
    'at': at.toUtc().toIso8601String(),
    'appVersion': appVersion,
    'locale': locale,
    'platform': Platform.operatingSystem,
    ...extra,
  };
}

/// Stores consent locally first (so the free app works offline with no
/// account) and syncs append-only records to Firestore when signed in.
class ConsentRepository {
  ConsentRepository({required this.store, required this.appVersion});

  final LocalStore store;
  final String appVersion;

  String _key(ConsentType t) => '${Keys.consentPrefix}${t.name}';

  Map<String, Object?>? latest(ConsentType t) => store.getJson(_key(t));

  /// True when the latest record accepts the current version.
  bool hasCurrent(ConsentType t) {
    final r = latest(t);
    return r != null && r['accepted'] == true && r['version'] == t.currentVersion;
  }

  /// True when a previous version was accepted but the text has since
  /// changed materially, so we must ask again.
  bool needsReconsent(ConsentType t) {
    final r = latest(t);
    return r != null && r['accepted'] == true && r['version'] != t.currentVersion;
  }

  Future<ConsentRecord> record(
    ConsentType type, {
    required bool accepted,
    required String locale,
    Map<String, Object?> extra = const {},
  }) async {
    final rec = ConsentRecord(
      type: type,
      version: type.currentVersion,
      accepted: accepted,
      at: DateTime.now(),
      appVersion: appVersion,
      locale: locale,
      extra: extra,
    );
    await store.setJson(_key(type), rec.toJson());
    final pending = [...store.getJsonList(Keys.consentPending), rec.toJson()];
    await store.setJsonList(Keys.consentPending, pending);
    return rec;
  }

  /// Uploads pending records to users/{uid}/consents. Records are
  /// append-only: security rules forbid updates and deletes.
  Future<void> syncPending(String uid) async {
    final pending = store.getJsonList(Keys.consentPending);
    if (pending.isEmpty) return;
    final col = FirebaseFirestore.instance.collection('users').doc(uid).collection('consents');
    final remaining = <Map<String, Object?>>[];
    for (final r in pending) {
      try {
        await col.add({...r, 'serverAt': FieldValue.serverTimestamp()});
      } on Object catch (e) {
        debugPrint('consent sync failed: $e');
        remaining.add(r);
      }
    }
    await store.setJsonList(Keys.consentPending, remaining);
  }
}

final appVersionProvider = Provider<String>((ref) => '0.0.0');

final consentRepositoryProvider = Provider<ConsentRepository>(
  (ref) => ConsentRepository(store: ref.watch(localStoreProvider), appVersion: ref.watch(appVersionProvider)),
);

/// Reactive view of which consents are current, so routes and screens update.
class ConsentState extends Notifier<Map<ConsentType, bool>> {
  @override
  Map<ConsentType, bool> build() {
    final repo = ref.watch(consentRepositoryProvider);
    return {for (final t in ConsentType.values) t: repo.hasCurrent(t)};
  }

  Future<void> set(ConsentType type, {required bool accepted, required String locale, Map<String, Object?> extra = const {}}) async {
    final repo = ref.read(consentRepositoryProvider);
    await repo.record(type, accepted: accepted, locale: locale, extra: extra);
    state = {...state, type: repo.hasCurrent(type)};
    await sync();
  }

  Future<void> sync() async {
    if (!ref.read(backendStatusProvider).firebaseReady) return;
    final user = await ref.read(authServiceProvider).ensureSignedIn();
    if (user == null) return;
    await ref.read(consentRepositoryProvider).syncPending(user.uid);
  }
}

final consentProvider = NotifierProvider<ConsentState, Map<ConsentType, bool>>(ConsentState.new);

/// Age gate result. Only the 18+ flag is kept, never the birth year.
@immutable
class AgeStatus {
  const AgeStatus({required this.passed, required this.isAdult, this.blockedUntil});

  final bool passed;
  final bool isAdult;
  final DateTime? blockedUntil;

  bool get blocked => blockedUntil != null && DateTime.now().isBefore(blockedUntil!);
}

class AgeController extends Notifier<AgeStatus> {
  @override
  AgeStatus build() {
    final store = ref.read(localStoreProvider);
    final blockedAt = store.getInt(Keys.ageBlockedAt);
    return AgeStatus(
      passed: store.getBool(Keys.agePassed),
      isAdult: store.getBool(Keys.ageIsAdult),
      blockedUntil: blockedAt == null ? null : DateTime.fromMillisecondsSinceEpoch(blockedAt).add(const Duration(days: 1)),
    );
  }

  /// Returns false (and blocks for a day) when under 13.
  Future<bool> submitBirthYear(int year, {required String locale, DateTime? now}) async {
    final today = now ?? DateTime.now();
    // Without the month, someone born in [year] is (today.year - year - 1) or
    // (today.year - year). Use the younger possibility so we never treat a
    // 12-year-old as 13 or a 17-year-old as an adult.
    final minAge = today.year - year - 1;
    final store = ref.read(localStoreProvider);
    if (minAge < 13) {
      await store.setInt(Keys.ageBlockedAt, today.millisecondsSinceEpoch);
      await store.setBool(Keys.agePassed, false);
      state = AgeStatus(passed: false, isAdult: false, blockedUntil: today.add(const Duration(days: 1)));
      return false;
    }
    final isAdult = minAge >= 18;
    await store.setBool(Keys.agePassed, true);
    await store.setBool(Keys.ageIsAdult, isAdult);
    await store.remove(Keys.ageBlockedAt);
    state = AgeStatus(passed: true, isAdult: isAdult);
    await ref.read(consentProvider.notifier).set(ConsentType.age, accepted: true, locale: locale, extra: {'isAdult': isAdult});
    return true;
  }
}

final ageProvider = NotifierProvider<AgeController, AgeStatus>(AgeController.new);
