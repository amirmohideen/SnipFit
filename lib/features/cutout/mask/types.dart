import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

/// Classes of MediaPipe's multi-class selfie segmenter (selfie_multiclass_256x256).
abstract final class SegClass {
  static const background = 0;
  static const hair = 1;
  static const bodySkin = 2;
  static const faceSkin = 3;
  static const clothes = 4;

  /// Accessories: hats, scarves, glasses and similar.
  static const other = 5;
  static const count = 6;
}

/// Per-class probabilities at model resolution, as produced by the segmenter.
/// [data] is interleaved: `data[(y * width + x) * 6 + class]`.
/// The model input was letterboxed; the pad fields are fractions of the model
/// frame that hold no image.
class ClassProbabilities {
  ClassProbabilities({
    required this.width,
    required this.height,
    required this.data,
    this.padTop = 0,
    this.padBottom = 0,
    this.padLeft = 0,
    this.padRight = 0,
  }) : assert(data.length == width * height * SegClass.count);

  final int width;
  final int height;
  final Float32List data;
  final double padTop;
  final double padBottom;
  final double padLeft;
  final double padRight;
}

/// Face geometry in image pixel coordinates. Lives in memory only: it is
/// never written to disk or sent anywhere.
class FaceGeometry {
  const FaceGeometry({
    required this.box,
    required this.eyeA,
    required this.eyeB,
    this.nose,
    this.mouth,
    this.oval,
    this.yaw,
    this.pitch,
    this.roll,
    this.score = 1,
  });

  final Rect box;

  /// The two eye centers, in either order.
  final Offset eyeA;
  final Offset eyeB;
  final Offset? nose;
  final Offset? mouth;

  /// Ordered face-oval contour, when the detector produced a mesh.
  final List<Offset>? oval;
  final double? yaw;
  final double? pitch;
  final double? roll;
  final double score;

  /// Eye on the image's left side.
  Offset get leftEye => eyeA.dx <= eyeB.dx ? eyeA : eyeB;

  /// Eye on the image's right side.
  Offset get rightEye => eyeA.dx <= eyeB.dx ? eyeB : eyeA;
  Offset get eyeMid => (eyeA + eyeB) / 2;
  double get interocular => (rightEye - leftEye).distance;

  /// In-plane rotation of the eye line, radians.
  double get eyeLineAngle {
    final d = rightEye - leftEye;
    return math.atan2(d.dy, d.dx);
  }
}

/// Hard class label and confidence (0-255) per pixel at working resolution.
class LabelMap {
  LabelMap({
    required this.width,
    required this.height,
    required this.labels,
    required this.confidence,
  });

  final int width;
  final int height;
  final Uint8List labels;
  final Uint8List confidence;

  int at(int x, int y) => labels[y * width + x];
}

/// A binary or alpha mask (0..255), row-major.
class Mask {
  Mask(this.width, this.height, [Uint8List? data])
    : data = data ?? Uint8List(width * height);

  final int width;
  final int height;
  final Uint8List data;

  Mask copy() => Mask(width, height, Uint8List.fromList(data));

  int get area {
    var n = 0;
    for (final v in data) {
      if (v > 127) n++;
    }
    return n;
  }

  bool get isEmpty => area == 0;
}
