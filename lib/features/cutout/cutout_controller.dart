
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics.dart';
import '../../core/analytics/analytics_events.dart';
import '../../core/images/image_utils.dart';
import '../../core/storage/media_store.dart';
import '../modes/app_mode.dart';
import 'cutout_isolates.dart';
import 'engine/segmentation_engine.dart';
import 'mask/hijab_template.dart';
import 'mask/mask_builder.dart';
import 'mask/photo_checks.dart';
import 'mask/types.dart';

enum CaptureSource { camera, upload }

/// Everything known about the photo being turned into a window. Lives in
/// memory only; face geometry and labels are dropped when the session ends.
class CutoutSession {
  CutoutSession({
    required this.photo,
    required this.mode,
    required this.someoneElse,
    required this.face,
    required this.labels,
    required this.checks,
    required this.result,
    required this.strategy,
    required this.style,
    required this.wearingDetected,
    this.editingWindowId,
  });

  final DecodedPhoto photo;
  final AppMode mode;
  final bool someoneElse;
  final FaceGeometry face;
  final LabelMap labels;
  final PhotoCheckResult checks;
  final MaskBuildResult result;
  final WindowStrategy strategy;
  final HijabStyle style;
  final bool wearingDetected;

  /// Set when re-editing a saved window.
  final String? editingWindowId;

  Mask get skin => result.skin;
}

sealed class CutoutState {
  const CutoutState();
}

class CutoutIdle extends CutoutState {
  const CutoutIdle();
}

class CutoutAnalyzing extends CutoutState {
  const CutoutAnalyzing();
}

/// A blocking problem (no face, more than one person) or a soft one the user
/// may override.
class CutoutNeedsFix extends CutoutState {
  const CutoutNeedsFix(this.issue, {this.pending});

  final PhotoIssue issue;

  /// Present for soft issues: the session to continue with on "Use anyway".
  final CutoutSession? pending;
}

class CutoutReady extends CutoutState {
  const CutoutReady(this.session);

  final CutoutSession session;
}

class CutoutFailed extends CutoutState {
  const CutoutFailed(this.error);

  final Object error;
}

class CutoutController extends Notifier<CutoutState> {
  @override
  CutoutState build() => const CutoutIdle();

  /// Analyzes a new photo: decode, detect, segment, check, build the window.
  Future<void> start(
    Uint8List bytes, {
    required CaptureSource source,
    required bool someoneElse,
    String? editingWindowId,
    WindowStrategy? strategyOverride,
    HijabStyle? styleOverride,
  }) async {
    state = const CutoutAnalyzing();
    final analytics = ref.read(analyticsProvider);
    if (editingWindowId == null) {
      await analytics.track(AnalyticsEvents.captureStarted, {AnalyticsProps.source: source.name});
    }
    try {
      final mode = ref.read(modeProvider);
      final photo = await ImageUtils.decode(bytes);
      final png = await ImageUtils.encodePng(photo.image);
      final output = await ref.read(segmentationEngineProvider).analyze(png);
      final luma = ImageUtils.luma(photo.rgba);
      final checks = checkPhoto(faces: output.faces, luma: luma, width: photo.width, height: photo.height);
      if (checks.blocking || output.classes == null) {
        photo.dispose();
        state = CutoutNeedsFix(checks.primary ?? PhotoIssue.noFace);
        return;
      }
      final faces = [...output.faces]
        ..sort((a, b) => (b.box.width * b.box.height).compareTo(a.box.width * a.box.height));
      final face = faces.first;
      final classes = output.classes!;
      final w = photo.width, h = photo.height;
      final labels = await upsampleLabelsInIsolate(classes, w, h);

      var strategy = strategyOverride ?? mode.defaultStrategy;
      var wearing = false;
      if (mode == AppMode.hijab && strategyOverride == null) {
        wearing = MaskBuilder.detectHijab(labels, face);
        strategy = wearing ? WindowStrategy.hijabWorn : WindowStrategy.hijabTemplate;
      }
      final style = styleOverride ?? HijabStyle.classicWrap;
      final result = await buildMaskInIsolate(labels: labels, face: face, strategy: strategy, style: style);
      final session = CutoutSession(
        photo: photo,
        mode: mode,
        someoneElse: someoneElse,
        face: face,
        labels: labels,
        checks: checks,
        result: result,
        strategy: strategy,
        style: style,
        wearingDetected: wearing,
        editingWindowId: editingWindowId,
      );
      if (editingWindowId == null) {
        await analytics.track(AnalyticsEvents.cutoutCompleted, {
          AnalyticsProps.quality: double.parse(result.quality.toStringAsFixed(2)),
          AnalyticsProps.mode: mode.name,
        });
      }
      state = checks.ok ? CutoutReady(session) : CutoutNeedsFix(checks.primary!, pending: session);
    } on Object catch (e, st) {
      debugPrint('cutout failed: $e\n$st');
      state = CutoutFailed(e);
    }
  }

  /// Continue despite a soft issue (light, pose, distance).
  void useAnyway() {
    final s = state;
    if (s is CutoutNeedsFix && s.pending != null) state = CutoutReady(s.pending!);
  }

  /// Switches between the worn-hijab cut and a hijab template, or changes
  /// the template style, without re-running the models.
  Future<void> rebuild({required WindowStrategy strategy, HijabStyle? style}) async {
    final s = state;
    if (s is! CutoutReady) return;
    final old = s.session;
    final labels = old.labels;
    final face = old.face;
    final nextStyle = style ?? old.style;
    final result = await buildMaskInIsolate(labels: labels, face: face, strategy: strategy, style: nextStyle);
    state = CutoutReady(
      CutoutSession(
        photo: old.photo,
        mode: old.mode,
        someoneElse: old.someoneElse,
        face: face,
        labels: labels,
        checks: old.checks,
        result: result,
        strategy: strategy,
        style: nextStyle,
        wearingDetected: old.wearingDetected,
        editingWindowId: old.editingWindowId,
      ),
    );
  }

  /// Saves the finished window and returns its record. Only the photo and
  /// the cutout are written; landmarks and class maps are discarded.
  Future<WindowRecord> save(Mask window, {required int softness}) async {
    final s = state;
    if (s is! CutoutReady) throw StateError('No cutout to save');
    final session = s.session;
    final photo = session.photo;
    final skin = session.skin;
    final alpha = await finalizeAlphaInIsolate(window, skin, softness);
    final rgba = photo.rgba;
    final cutoutRgba = await cutoutRgbaInIsolate(rgba, alpha.data);
    final cutoutImage = await ImageUtils.fromRgba(cutoutRgba, photo.width, photo.height);
    final cutoutPng = await ImageUtils.encodePng(cutoutImage);
    final photoJpeg = await ImageUtils.encodeJpeg(rgba, photo.width, photo.height, quality: 90);
    final thumb = await windowThumbnailInIsolate(cutoutRgba, photo.width, photo.height);
    cutoutImage.dispose();

    final store = ref.read(mediaStoreProvider);
    final record = WindowRecord(
      id: session.editingWindowId ?? MediaStore.newId(),
      mode: session.mode,
      createdAt: DateTime.now(),
      strategy: session.strategy,
      hijabStyle: session.strategy == WindowStrategy.hijabTemplate ? session.style : null,
      width: photo.width,
      height: photo.height,
      quality: session.result.quality,
      someoneElse: session.someoneElse,
    );
    await store.saveWindow(record, photoJpeg: photoJpeg, cutoutPng: cutoutPng, thumbJpeg: thumb);
    ref.read(mediaRevisionProvider.notifier).bump();
    return record;
  }

  void reset() {
    final s = state;
    if (s is CutoutReady) s.session.photo.dispose();
    if (s is CutoutNeedsFix) s.pending?.photo.dispose();
    state = const CutoutIdle();
  }
}

final cutoutControllerProvider = NotifierProvider<CutoutController, CutoutState>(CutoutController.new);
