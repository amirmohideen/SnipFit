import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'types.dart';

/// Problems found in a photo before building a window. Each maps to a single
/// one-line fix in the UI.
enum PhotoIssue {
  noFace,
  multipleFaces,
  tooDark,
  tooBright,
  notFrontal,
  tooFar;

  /// Hard issues can't be overridden: no face means no window, and more than
  /// one person is never allowed.
  bool get blocking => this == noFace || this == multipleFaces;
}

class PhotoCheckResult {
  const PhotoCheckResult(this.issues);

  final List<PhotoIssue> issues;

  bool get ok => issues.isEmpty;
  bool get blocking => issues.any((i) => i.blocking);
  PhotoIssue? get primary => issues.isEmpty ? null : issues.first;
}

/// Checks: one face only, enough light, frontal pose, close enough.
///
/// [luma] is an 8-bit grayscale copy of the photo at [width] x [height].
PhotoCheckResult checkPhoto({
  required List<FaceGeometry> faces,
  required Uint8List luma,
  required int width,
  required int height,
}) {
  if (faces.isEmpty) return const PhotoCheckResult([PhotoIssue.noFace]);
  // Ignore tiny background faces (posters, passers-by far away) only if they
  // are much smaller than the main face; otherwise it's two people.
  final sorted = [...faces]..sort((a, b) => (b.box.width * b.box.height).compareTo(a.box.width * a.box.height));
  final main = sorted.first;
  final mainArea = main.box.width * main.box.height;
  final others = sorted.skip(1).where((f) => f.box.width * f.box.height > mainArea * 0.12);
  if (others.isNotEmpty) return const PhotoCheckResult([PhotoIssue.multipleFaces]);

  final issues = <PhotoIssue>[];
  final mean = _meanLuma(luma, width, height, main.box);
  if (mean < 0.28) {
    issues.add(PhotoIssue.tooDark);
  } else if (mean > 0.9) {
    issues.add(PhotoIssue.tooBright);
  }
  final yaw = (main.yaw ?? 0).abs();
  final pitch = (main.pitch ?? 0).abs();
  final roll = (main.roll ?? 0).abs();
  if (yaw > 22 || pitch > 25 || roll > 18) issues.add(PhotoIssue.notFrontal);
  if (main.box.width < width * 0.12) issues.add(PhotoIssue.tooFar);
  return PhotoCheckResult(issues);
}

double _meanLuma(Uint8List luma, int w, int h, Rect box) {
  final x0 = box.left.clamp(0, w - 1).toInt();
  final x1 = box.right.clamp(0, w - 1).toInt();
  final y0 = box.top.clamp(0, h - 1).toInt();
  final y1 = box.bottom.clamp(0, h - 1).toInt();
  if (x1 <= x0 || y1 <= y0) return 0.5;
  var sum = 0;
  var n = 0;
  for (var y = y0; y <= y1; y += 2) {
    for (var x = x0; x <= x1; x += 2) {
      sum += luma[y * w + x];
      n++;
    }
  }
  return n == 0 ? 0.5 : sum / n / 255;
}
