import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:face_detection_tflite/face_detection_tflite.dart' as fdt;

import '../mask/types.dart';
import 'segmentation_engine.dart';

/// [SegmentationEngine] backed by the face_detection_tflite package, which
/// wraps MediaPipe's face detector, face mesh and the multi-class selfie
/// segmenter (selfie_multiclass_256x256).
///
/// Acceleration follows the spec: GPU on iOS, CPU on Android (where GPU
/// delegate support is unreliable across devices).
///
/// Fallback if this package ever misbehaves: run selfie_multiclass_256x256
/// directly with flutter_litert/tflite_flutter behind this same interface.
class TfliteSegmentationEngine implements SegmentationEngine {
  fdt.FaceDetector? _detector;
  Future<fdt.FaceDetector>? _loading;

  Future<fdt.FaceDetector> _ensure() {
    if (_detector != null) return Future.value(_detector);
    return _loading ??= () async {
      final detector = await fdt.FaceDetector.create(
        withSegmentation: true,
        performanceConfig: Platform.isIOS
            ? const fdt.PerformanceConfig.gpu()
            : const fdt.PerformanceConfig.xnnpack(numThreads: 4),
        segmentationConfig: fdt.SegmentationConfig(
          model: fdt.SegmentationModel.multiclass,
          performanceConfig: Platform.isIOS
              ? const fdt.PerformanceConfig.auto()
              : fdt.PerformanceConfig.disabled,
          maxOutputSize: 1024,
        ),
      );
      _detector = detector;
      return detector;
    }();
  }

  @override
  Future<void> warmUp() => _ensure();

  @override
  Future<SegmentationOutput> analyze(Uint8List encodedImage) async {
    final detector = await _ensure();
    final result = await detector.detectFacesWithSegmentation(
      encodedImage,
      mode: fdt.FaceDetectionMode.standard,
    );
    final faces = [for (final f in result.faces) _toGeometry(f)];
    final mask = result.segmentationMask;
    ClassProbabilities? classes;
    if (mask is fdt.MulticlassSegmentationMask) {
      final pad = mask.padding;
      classes = ClassProbabilities(
        width: mask.width,
        height: mask.height,
        data: mask.internalClassData,
        padTop: pad[0],
        padBottom: pad[1],
        padLeft: pad[2],
        padRight: pad[3],
      );
    }
    return SegmentationOutput(faces: faces, classes: classes);
  }

  FaceGeometry _toGeometry(fdt.Face f) {
    final b = f.boundingBox;
    final lm = f.landmarks;
    Offset? o(fdt.Point? p) => p == null ? null : Offset(p.x, p.y);
    final eyeA = o(lm.leftEye) ?? Offset(b.topLeft.x + b.width * 0.3, b.topLeft.y + b.height * 0.4);
    final eyeB = o(lm.rightEye) ?? Offset(b.topLeft.x + b.width * 0.7, b.topLeft.y + b.height * 0.4);
    final oval = f.getContour(fdt.FaceContourType.face);
    return FaceGeometry(
      box: Rect.fromLTWH(b.topLeft.x, b.topLeft.y, b.width, b.height),
      eyeA: eyeA,
      eyeB: eyeB,
      nose: o(lm.noseTip),
      mouth: o(lm.mouth),
      oval: oval == null ? null : [for (final p in oval) Offset(p.x, p.y)],
      yaw: f.headEulerAngleY,
      pitch: f.headEulerAngleX,
      roll: f.headEulerAngleZ,
      score: f.score,
    );
  }

  @override
  Future<void> dispose() async {
    await _detector?.dispose();
    _detector = null;
    _loading = null;
  }
}
