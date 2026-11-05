import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Push notifications, used for exactly one thing: "your AI try-on is ready".
abstract class Notifications {
  Future<bool> requestPermission();

  /// Registers this device's push token under users/{uid}/devices.
  Future<void> registerDevice(String uid);

  /// Try-on request IDs from notifications the user tapped.
  Stream<String> get openedTryOns;
}

class NoopNotifications implements Notifications {
  const NoopNotifications();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> registerDevice(String uid) async {}

  @override
  Stream<String> get openedTryOns => const Stream.empty();
}

class FirebaseNotifications implements Notifications {
  FirebaseNotifications() {
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpen);
    FirebaseMessaging.instance.getInitialMessage().then((m) {
      if (m != null) _handleOpen(m);
    });
  }

  final _opened = StreamController<String>.broadcast();
  final _messaging = FirebaseMessaging.instance;

  void _handleOpen(RemoteMessage m) {
    final id = m.data['requestId'];
    if (id is String && id.isNotEmpty) _opened.add(id);
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<void> registerDevice(String uid) async {
    try {
      // getToken is deprecated in favour of register()/onRegistered (an
      // installation ID). Keep the registration token until the server's
      // send path is moved to the new target type.
      // ignore: deprecated_member_use
      final token = await _messaging.getToken();
      if (token == null) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).collection('devices').doc(token).set({
        'token': token,
        'platform': defaultTargetPlatform.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on Object catch (e) {
      debugPrint('push registration skipped: $e');
    }
  }

  @override
  Stream<String> get openedTryOns => _opened.stream;
}

final notificationsProvider = Provider<Notifications>((ref) => const NoopNotifications());
