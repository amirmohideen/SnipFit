import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_config.dart';
import '../../core/backend/auth_service.dart';
import '../../core/storage/local_store.dart';
import '../modes/app_mode.dart';

/// Invite links on our own domain: `https://<domain>/i/<code>?m=<mode>`.
/// They open the app through universal links / App Links, or the store's
/// custom product page for that mode when the app isn't installed.
class InviteLinks {
  InviteLinks({required this.domain, required this.seed});

  final String domain;
  final String seed;

  /// Short, non-reversible code derived from the account or install ID.
  static String codeFor(String seed) {
    final digest = sha256.convert(utf8.encode('snipfit-invite:$seed')).bytes;
    const alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
    return [for (var i = 0; i < 8; i++) alphabet[digest[i] % alphabet.length]].join();
  }

  Uri link(AppMode mode) => Uri.https(domain, '/i/${codeFor(seed)}', {'m': mode.name});

  /// Parses an incoming invite link. Returns the mode it points to, or null
  /// if the URI isn't an invite.
  static ({AppMode? mode})? parse(Uri uri) {
    if (uri.pathSegments.isEmpty || uri.pathSegments.first != 'i') return null;
    return (mode: AppMode.tryParse(uri.queryParameters['m']));
  }
}

final inviteLinksProvider = Provider<InviteLinks>((ref) {
  final config = ref.watch(appConfigProvider);
  final uid = ref.watch(currentUserProvider).value?.uid;
  return InviteLinks(domain: config.webDomain, seed: uid ?? ref.watch(localStoreProvider).installId);
});
