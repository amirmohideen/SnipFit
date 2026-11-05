import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Crash reporting. Never attach images, photos or personal details.
abstract class CrashReporter {
  void recordError(Object error, StackTrace? stack, {bool fatal = false});
  void log(String message);
  Future<void> setEnabled(bool enabled);
}

class DebugCrashReporter implements CrashReporter {
  const DebugCrashReporter();

  @override
  void recordError(Object error, StackTrace? stack, {bool fatal = false}) {
    debugPrint('[crash${fatal ? ' fatal' : ''}] $error\n$stack');
  }

  @override
  void log(String message) => debugPrint('[crash-log] $message');

  @override
  Future<void> setEnabled(bool enabled) async {}
}

class FirebaseCrashReporter implements CrashReporter {
  FirebaseCrashReporter(this._crashlytics);

  final FirebaseCrashlytics _crashlytics;

  @override
  void recordError(Object error, StackTrace? stack, {bool fatal = false}) {
    _crashlytics.recordError(error, stack, fatal: fatal);
  }

  @override
  void log(String message) => _crashlytics.log(message);

  @override
  Future<void> setEnabled(bool enabled) =>
      _crashlytics.setCrashlyticsCollectionEnabled(enabled && !kDebugMode);
}

final crashReporterProvider = Provider<CrashReporter>(
  (ref) => const DebugCrashReporter(),
);
