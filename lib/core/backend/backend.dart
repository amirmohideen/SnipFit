import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the app could connect to at startup. The free features never depend
/// on any of this; paid features check it and explain when unavailable.
@immutable
class BackendStatus {
  const BackendStatus({required this.firebaseReady});

  /// False until `flutterfire configure` has been run for this flavor.
  final bool firebaseReady;
}

final backendStatusProvider = Provider<BackendStatus>(
  (ref) => const BackendStatus(firebaseReady: false),
);
