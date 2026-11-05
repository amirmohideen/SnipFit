import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend/auth_service.dart';
import '../../core/backend/backend.dart';
import 'purchases_service.dart';

/// What the person can use right now.
@immutable
class Entitlements {
  const Entitlements({this.isPro = false, this.credits = 0, this.allowanceLeft = 0, this.suspended = false});

  /// Pro removes the watermark and includes monthly AI try-ons.
  final bool isPro;

  /// Purchased AI credits (from the server ledger).
  final int credits;

  /// Pro's monthly AI try-ons left this period.
  final int allowanceLeft;
  final bool suspended;

  int get aiTryOnsAvailable => credits + allowanceLeft;
}

/// Pro status comes from RevenueCat on the device (for instant UI) and the
/// credit balance from the server ledger in Firestore, which only Cloud
/// Functions and the RevenueCat webhook can write.
final entitlementsProvider = Provider<Entitlements>((ref) {
  final isPro = ref.watch(proStatusProvider).value ?? false;
  final ledger = ref.watch(ledgerProvider).value;
  return Entitlements(
    isPro: isPro || (ledger?.proActive ?? false),
    credits: ledger?.credits ?? 0,
    allowanceLeft: ledger?.allowanceLeft ?? 0,
    suspended: ledger?.suspended ?? false,
  );
});

@immutable
class LedgerSnapshot {
  const LedgerSnapshot({required this.credits, required this.allowanceLeft, required this.proActive, required this.suspended});

  final int credits;
  final int allowanceLeft;
  final bool proActive;
  final bool suspended;

  static LedgerSnapshot fromDoc(Map<String, dynamic>? d) {
    if (d == null) return const LedgerSnapshot(credits: 0, allowanceLeft: 0, proActive: false, suspended: false);
    final credits = (d['credits'] as Map?)?.cast<String, dynamic>() ?? const {};
    final allowance = (d['allowance'] as Map?)?.cast<String, dynamic>() ?? const {};
    final pro = (d['pro'] as Map?)?.cast<String, dynamic>() ?? const {};
    final suspendedUntil = d['suspendedUntil'];
    final purchased = (credits['balance'] as num?)?.toInt() ?? 0;
    final reserved = (credits['reserved'] as num?)?.toInt() ?? 0;
    final limit = (allowance['limit'] as num?)?.toInt() ?? 0;
    final used = (allowance['used'] as num?)?.toInt() ?? 0;
    final expires = pro['expiresAt'];
    final proActive =
        pro['active'] == true && (expires is! Timestamp || expires.toDate().isAfter(DateTime.now()));
    return LedgerSnapshot(
      credits: (purchased - reserved).clamp(0, 1 << 30),
      allowanceLeft: proActive ? (limit - used).clamp(0, limit) : 0,
      proActive: proActive,
      suspended: suspendedUntil is Timestamp && suspendedUntil.toDate().isAfter(DateTime.now()),
    );
  }
}

final ledgerProvider = StreamProvider<LedgerSnapshot?>((ref) {
  if (!ref.watch(backendStatusProvider).firebaseReady) return Stream.value(null);
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .snapshots()
      .map((s) => LedgerSnapshot.fromDoc(s.data()));
});
