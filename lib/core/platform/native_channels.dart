
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin Dart wrappers around Snipfit's own native code (see
/// ios/Runner/*.swift and android/app/src/main/kotlin/**). Every call
/// degrades gracefully when the native side is missing (tests, desktop).
abstract final class NativeChannels {
  static const _platform = MethodChannel('snipfit/platform');
  static const _video = MethodChannel('snipfit/video');
  static const _share = MethodChannel('snipfit/share');
  static const _tap = MethodChannel('snipfit/tap_segmenter');

  /// Keeps private photos out of iCloud/device backups (iOS). On Android,
  /// backups are disabled in the manifest instead.
  static Future<void> excludeFromBackup(String path) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _platform.invokeMethod<void>('excludeFromBackup', {'path': path});
    } on Object catch (e) {
      debugPrint('excludeFromBackup unavailable: $e');
    }
  }

  // ---------------------------------------------------------------- video

  /// Starts an H.264 MP4 encoder (AVAssetWriter on iOS, MediaCodec on Android).
  static Future<bool> videoStart({
    required String path,
    required int width,
    required int height,
    required int fps,
    int bitrate = 6000000,
  }) async {
    try {
      return await _video.invokeMethod<bool>('start', {
            'path': path,
            'width': width,
            'height': height,
            'fps': fps,
            'bitrate': bitrate,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Appends one RGBA frame (width * height * 4 bytes).
  static Future<void> videoAddFrame(Uint8List rgba) =>
      _video.invokeMethod<void>('addFrame', {'rgba': rgba});

  /// Finishes the file. Returns true when the MP4 was written.
  static Future<bool> videoFinish() async => await _video.invokeMethod<bool>('finish') ?? false;

  static Future<void> videoCancel() async {
    try {
      await _video.invokeMethod<void>('cancel');
    } on Object {
      // Nothing to clean up.
    }
  }

  // ---------------------------------------------------------------- share

  /// Whether a share target app is installed. [target] is one of
  /// instagram, tiktok, snapchat, whatsapp.
  static Future<bool> isInstalled(String target) async {
    try {
      return await _share.invokeMethod<bool>('isInstalled', {'target': target}) ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Shares to a specific app via its official mechanism where available
  /// (Instagram Stories, TikTok Share Kit, Snapchat Creative Kit), or a
  /// targeted share intent on Android. Returns false when unavailable, in
  /// which case the caller falls back to the system share sheet.
  static Future<bool> shareTo({
    required String target,
    required String path,
    required String mimeType,
    required Map<String, String> appIds,
    String? caption,
  }) async {
    try {
      return await _share.invokeMethod<bool>('shareTo', {
            'target': target,
            'path': path,
            'mimeType': mimeType,
            'appIds': appIds,
            'caption': ?caption,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('shareTo($target) failed: ${e.code} ${e.message}');
      return false;
    }
  }

  // ------------------------------------------------------- tap segmenter

  /// True when this device can run tap-to-select (Android with MediaPipe's
  /// Interactive Segmenter, or iOS 17+ with Vision instance masks).
  static Future<bool> tapSegmenterAvailable() async {
    try {
      return await _tap.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Returns an 8-bit mask (PNG, same size as the image) of the object under
  /// the normalized point ([x], [y] in 0..1), or null if nothing was found.
  static Future<Uint8List?> tapSegment({required String imagePath, required double x, required double y}) async {
    try {
      return await _tap.invokeMethod<Uint8List>('segment', {'path': imagePath, 'x': x, 'y': y});
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('tapSegment failed: ${e.code} ${e.message}');
      return null;
    }
  }
}
