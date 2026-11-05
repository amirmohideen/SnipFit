import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/backend/auth_service.dart';
import '../../core/storage/local_store.dart';
import '../../core/storage/media_store.dart';
import '../modes/app_mode.dart';

enum TryOnPhase { queued, checking, generating, finishing, succeeded, blocked, failed }

@immutable
class TryOnStatus {
  const TryOnStatus({required this.id, required this.phase, this.resultPaths = const [], this.errorCode});

  final String id;
  final TryOnPhase phase;
  final List<String> resultPaths;
  final String? errorCode;

  bool get done => phase == TryOnPhase.succeeded || phase == TryOnPhase.blocked || phase == TryOnPhase.failed;

  static TryOnStatus fromDoc(String id, Map<String, dynamic>? d) => TryOnStatus(
    id: id,
    phase: TryOnPhase.values.firstWhere((p) => p.name == d?['status'], orElse: () => TryOnPhase.queued),
    resultPaths: [for (final p in (d?['resultPaths'] as List?) ?? const []) p as String],
    errorCode: (d?['error'] as Map?)?['code'] as String?,
  );
}

/// Why a request could not start, mapped from the server's error codes.
enum TryOnRejection { noCredits, rateLimited, dailyCap, consent, notAdult, suspended, unavailable, unknown }

class TryOnRejected implements Exception {
  const TryOnRejected(this.reason);

  final TryOnRejection reason;
}

/// Talks to the try-on Cloud Functions. Photos leave the phone only here,
/// only after AI consent, and only for a paid request.
class TryOnRepository {
  TryOnRepository(this._ref);

  final Ref _ref;

  /// Hashed install ID for per-device rate limits (not tied to hardware).
  String get _deviceKey => sha256.convert(utf8.encode(_ref.read(localStoreProvider).installId)).toString().substring(0, 24);

  File referencePhotoFile() => File('${_ref.read(mediaStoreProvider).aiDir.path}/reference.jpg');

  Future<bool> hasReferencePhoto() => referencePhotoFile().exists();

  Future<void> saveReferencePhoto(Uint8List jpeg) async {
    final f = referencePhotoFile();
    await f.parent.create(recursive: true);
    await f.writeAsBytes(jpeg, flush: true);
  }

  Future<void> deleteReferencePhoto() async {
    final f = referencePhotoFile();
    if (await f.exists()) await f.delete();
  }

  Future<String> submit({required Uint8List garmentPng, required AppMode mode}) async {
    final user = await _ref.read(authServiceProvider).ensureSignedIn();
    if (user == null) throw const TryOnRejected(TryOnRejection.unavailable);
    final person = await referencePhotoFile().readAsBytes();
    final id = const Uuid().v4();
    final folder = FirebaseStorage.instance.ref('tryon-inputs/${user.uid}/$id');
    await folder.child('person.jpg').putData(person, SettableMetadata(contentType: 'image/jpeg'));
    await folder.child('garment.png').putData(garmentPng, SettableMetadata(contentType: 'image/png'));
    try {
      await FirebaseFunctions.instance.httpsCallable('createTryOn').call<void>({
        'requestId': id,
        'mode': mode.name,
        'deviceKey': _deviceKey,
      });
    } on FirebaseFunctionsException catch (e) {
      final reason = switch ((e.code, e.details is Map ? (e.details as Map)['reason'] : null)) {
        ('resource-exhausted', 'no_credits') => TryOnRejection.noCredits,
        ('resource-exhausted', 'daily_cap') => TryOnRejection.dailyCap,
        ('resource-exhausted', _) => TryOnRejection.rateLimited,
        ('failed-precondition', 'not_adult') => TryOnRejection.notAdult,
        ('failed-precondition', _) => TryOnRejection.consent,
        ('permission-denied', _) => TryOnRejection.suspended,
        ('unavailable', _) => TryOnRejection.unavailable,
        _ => TryOnRejection.unknown,
      };
      throw TryOnRejected(reason);
    }
    return id;
  }

  Stream<TryOnStatus> watch(String id) => FirebaseFirestore.instance
      .collection('tryonRequests')
      .doc(id)
      .snapshots()
      .map((s) => TryOnStatus.fromDoc(id, s.data()));

  /// Downloads results into private storage; the server deletes its copies
  /// within 24 hours.
  Future<List<File>> download(TryOnStatus status) async {
    final dir = Directory('${_ref.read(mediaStoreProvider).aiDir.path}/results/${status.id}');
    await dir.create(recursive: true);
    final files = <File>[];
    for (var i = 0; i < status.resultPaths.length; i++) {
      final f = File('${dir.path}/result_$i.png');
      if (!await f.exists()) await FirebaseStorage.instance.ref(status.resultPaths[i]).writeToFile(f);
      files.add(f);
    }
    return files;
  }

  Future<void> report(String requestId, String reason) =>
      FirebaseFunctions.instance.httpsCallable('reportResult').call<void>({'requestId': requestId, 'reason': reason});
}

final tryOnRepositoryProvider = Provider<TryOnRepository>(TryOnRepository.new);

final referencePhotoExistsProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(tryOnRepositoryProvider).hasReferencePhoto(),
);
