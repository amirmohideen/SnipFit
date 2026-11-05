import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// The signed-in account. Anonymous by default; linking Apple or Google keeps
/// credits across devices. We never read the account's name or email.
@immutable
class AppUser {
  const AppUser({
    required this.uid,
    required this.isAnonymous,
    required this.providers,
  });

  final String uid;
  final bool isAnonymous;
  final Set<String> providers;

  bool get hasApple => providers.contains('apple.com');
  bool get hasGoogle => providers.contains('google.com');
}

enum LinkOutcome { linked, switchedAccount, cancelled, failed }

abstract class AuthService {
  Stream<AppUser?> get userChanges;
  AppUser? get currentUser;

  /// Signs in anonymously if needed. Returns null when offline.
  Future<AppUser?> ensureSignedIn();
  Future<LinkOutcome> linkWithApple();
  Future<LinkOutcome> linkWithGoogle();
  Future<void> signOut();

  /// Deletes the account and all server-side data, then signs out.
  Future<void> deleteAccount();
}

/// Used when Firebase is not configured: there is no account at all.
class UnavailableAuthService implements AuthService {
  const UnavailableAuthService();

  @override
  Stream<AppUser?> get userChanges => Stream.value(null);

  @override
  AppUser? get currentUser => null;

  @override
  Future<AppUser?> ensureSignedIn() async => null;

  @override
  Future<LinkOutcome> linkWithApple() async => LinkOutcome.failed;

  @override
  Future<LinkOutcome> linkWithGoogle() async => LinkOutcome.failed;

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({required this.googleServerClientId});

  final String googleServerClientId;
  final _auth = FirebaseAuth.instance;
  bool _googleInitialized = false;

  AppUser? _map(User? user) => user == null
      ? null
      : AppUser(
          uid: user.uid,
          isAnonymous: user.isAnonymous,
          providers: user.providerData.map((p) => p.providerId).toSet(),
        );

  @override
  Stream<AppUser?> get userChanges => _auth.userChanges().map(_map);

  @override
  AppUser? get currentUser => _map(_auth.currentUser);

  @override
  Future<AppUser?> ensureSignedIn() async {
    if (_auth.currentUser != null) return currentUser;
    try {
      await _auth.signInAnonymously();
    } on FirebaseAuthException {
      return null;
    }
    return currentUser;
  }

  Future<LinkOutcome> _linkOrSwitch(AuthCredential credential) async {
    final user = _auth.currentUser ?? (await _auth.signInAnonymously()).user!;
    try {
      await user.linkWithCredential(credential);
      return LinkOutcome.linked;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use' ||
          e.code == 'email-already-in-use' ||
          e.code == 'provider-already-linked') {
        // The Apple/Google account already has a Snipfit account (for
        // example from another phone): switch to it so its credits follow.
        await _auth.signInWithCredential(e.credential ?? credential);
        return LinkOutcome.switchedAccount;
      }
      return LinkOutcome.failed;
    }
  }

  @override
  Future<LinkOutcome> linkWithApple() async {
    try {
      if (Platform.isIOS) {
        final rawNonce = _nonce();
        final apple = await SignInWithApple.getAppleIDCredential(
          scopes: const [],
          nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
        );
        final credential = OAuthProvider('apple.com').credential(
          idToken: apple.identityToken,
          rawNonce: rawNonce,
          accessToken: apple.authorizationCode,
        );
        return await _linkOrSwitch(credential);
      }
      // Android: Firebase runs Apple's web flow.
      final user = _auth.currentUser ?? (await _auth.signInAnonymously()).user!;
      try {
        await user.linkWithProvider(AppleAuthProvider());
        return LinkOutcome.linked;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'credential-already-in-use' && e.credential != null) {
          await _auth.signInWithCredential(e.credential!);
          return LinkOutcome.switchedAccount;
        }
        if (e.code == 'web-context-canceled') return LinkOutcome.cancelled;
        return LinkOutcome.failed;
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      return e.code == AuthorizationErrorCode.canceled
          ? LinkOutcome.cancelled
          : LinkOutcome.failed;
    }
  }

  @override
  Future<LinkOutcome> linkWithGoogle() async {
    try {
      if (!_googleInitialized) {
        await GoogleSignIn.instance.initialize(
          serverClientId: googleServerClientId.isEmpty
              ? null
              : googleServerClientId,
        );
        _googleInitialized = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) return LinkOutcome.failed;
      return await _linkOrSwitch(GoogleAuthProvider.credential(idToken: idToken));
    } on GoogleSignInException catch (e) {
      return e.code == GoogleSignInExceptionCode.canceled
          ? LinkOutcome.cancelled
          : LinkOutcome.failed;
    }
  }

  @override
  Future<void> signOut() async {
    if (_googleInitialized) await GoogleSignIn.instance.signOut();
    await _auth.signOut();
    await ensureSignedIn();
  }

  @override
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    // Apple requires revoking Sign in with Apple tokens on deletion.
    if (Platform.isIOS && currentUser!.hasApple) {
      try {
        final apple = await SignInWithApple.getAppleIDCredential(
          scopes: const [],
        );
        await _auth.revokeTokenWithAuthorizationCode(apple.authorizationCode);
      } on Object catch (e) {
        debugPrint('Apple token revocation skipped: $e');
      }
    }
    // The server deletes Firestore data, stored AI inputs and results,
    // RevenueCat subscriber data and finally the auth user.
    await FirebaseFunctions.instance.httpsCallable('deleteAccount').call<void>();
    await _auth.signOut();
  }

  static String _nonce([int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }
}

final authServiceProvider = Provider<AuthService>(
  (ref) => const UnavailableAuthService(),
);

final currentUserProvider = StreamProvider<AppUser?>((ref) {
  final auth = ref.watch(authServiceProvider);
  return auth.userChanges;
});
