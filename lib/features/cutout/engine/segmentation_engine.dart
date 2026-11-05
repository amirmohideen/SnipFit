import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mask/types.dart';
import 'tflite_engine.dart';

/// Result of analyzing one photo. Everything here stays in memory: landmarks
/// and class maps are never stored or sent.
class SegmentationOutput {
  SegmentationOutput({required this.faces, required this.classes});

  final List<FaceGeometry> faces;
  final ClassProbabilities? classes;
}

/// On-device face detection + multi-class selfie segmentation.
abstract class SegmentationEngine {
  /// [encodedImage] is a PNG or JPEG at working resolution; returned
  /// coordinates are in that image's pixel space.
  Future<SegmentationOutput> analyze(Uint8List encodedImage);

  /// Loads models ahead of time so the first cutout is fast.
  Future<void> warmUp();

  Future<void> dispose();
}

final segmentationEngineProvider = Provider<SegmentationEngine>((ref) {
  final engine = TfliteSegmentationEngine();
  ref.onDispose(engine.dispose);
  return engine;
});
