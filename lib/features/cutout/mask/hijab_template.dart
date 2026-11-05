import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'mask_ops.dart';
import 'types.dart';

/// Named hijab styles offered when the person in the photo is not wearing a
/// hijab. Hijabi testers should confirm this set before launch.
enum HijabStyle { classicWrap, khimar, shayla }

/// A coordinate frame anchored on the eyes: origin at the eye midpoint,
/// x along the eye line (towards the image's right), y pointing down the face,
/// one unit = the distance between the eyes. Templates are drawn in this
/// frame so they follow the head's position, size and tilt.
class FaceFrame {
  FaceFrame(FaceGeometry face)
    : origin = face.eyeMid,
      unit = face.interocular,
      angle = face.eyeLineAngle;

  final Offset origin;
  final double unit;
  final double angle;

  Offset toImage(Offset p) {
    final c = math.cos(angle), s = math.sin(angle);
    final x = p.dx * unit, y = p.dy * unit;
    return origin + Offset(x * c - y * s, x * s + y * c);
  }

  Offset toFace(Offset q) {
    final d = q - origin;
    final c = math.cos(-angle), s = math.sin(-angle);
    return Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c) / unit;
  }

  List<Offset> polygonToImage(List<Offset> pts) => [for (final p in pts) toImage(p)];
}

abstract final class HijabTemplate {
  static List<Offset> _mirrored(List<Offset> rightHalf) {
    // rightHalf runs from the top center clockwise to the bottom center.
    final left = [
      for (final p in rightHalf.reversed.skip(1).take(rightHalf.length - 2))
        Offset(-p.dx, p.dy),
    ];
    return [...rightHalf, ...left];
  }

  /// Control points of each style's outline, in [FaceFrame] units. These are
  /// the editable handles shown in Refine.
  static List<Offset> controlPoints(HijabStyle style) => switch (style) {
    HijabStyle.classicWrap => _mirrored(const [
      Offset(0, -2.05),
      Offset(0.85, -1.9),
      Offset(1.35, -1.35),
      Offset(1.55, -0.45),
      Offset(1.55, 0.6),
      Offset(1.45, 1.6),
      Offset(1.6, 2.35),
      Offset(2.3, 2.85),
      Offset(2.95, 3.25),
      Offset(3.15, 3.9),
      Offset(2.8, 4.6),
      Offset(1.9, 5.0),
      Offset(0.9, 5.2),
      Offset(0, 5.25),
    ]),
    HijabStyle.khimar => _mirrored(const [
      Offset(0, -2.1),
      Offset(0.9, -1.95),
      Offset(1.4, -1.4),
      Offset(1.6, -0.45),
      Offset(1.62, 0.65),
      Offset(1.6, 1.7),
      Offset(1.95, 2.5),
      Offset(2.9, 3.2),
      Offset(3.6, 4.1),
      Offset(3.95, 5.4),
      Offset(4.05, 6.8),
      Offset(3.2, 7.4),
      Offset(1.6, 7.6),
      Offset(0, 7.65),
    ]),
    // Asymmetric: wrapped close around the neck on one side, one end draped
    // long over the other shoulder.
    HijabStyle.shayla => const [
      Offset(0, -2.05),
      Offset(0.85, -1.9),
      Offset(1.35, -1.35),
      Offset(1.55, -0.45),
      Offset(1.55, 0.6),
      Offset(1.5, 1.55),
      Offset(1.7, 2.3),
      Offset(2.4, 2.9),
      Offset(3.0, 3.4),
      Offset(3.25, 4.4),
      Offset(3.15, 5.8),
      Offset(2.6, 6.3),
      Offset(2.05, 5.6),
      Offset(1.7, 4.4),
      Offset(1.1, 3.3),
      Offset(0.1, 2.9),
      Offset(-0.9, 2.75),
      Offset(-1.5, 2.45),
      Offset(-1.6, 1.6),
      Offset(-1.6, 0.6),
      Offset(-1.6, -0.45),
      Offset(-1.38, -1.35),
      Offset(-0.88, -1.9),
    ],
  };

  /// Generous envelope of where a worn hijab can be, used to limit the
  /// segmentation-based hijab window to the head and neck region.
  static List<Offset> headNeckEnvelope() => _mirrored(const [
    Offset(0, -2.7),
    Offset(1.4, -2.35),
    Offset(2.05, -1.3),
    Offset(2.15, 0.3),
    Offset(2.05, 1.6),
    Offset(2.7, 2.5),
    Offset(3.8, 3.2),
    Offset(4.3, 4.4),
    Offset(4.3, 5.4),
    Offset(0, 5.6),
  ]);

  /// Closed Catmull-Rom curve through [pts].
  static List<Offset> smoothClosed(List<Offset> pts, {int samplesPerSegment = 10}) {
    final n = pts.length;
    if (n < 3) return pts;
    final out = <Offset>[];
    for (var i = 0; i < n; i++) {
      final p0 = pts[(i - 1 + n) % n];
      final p1 = pts[i];
      final p2 = pts[(i + 1) % n];
      final p3 = pts[(i + 2) % n];
      for (var s = 0; s < samplesPerSegment; s++) {
        final t = s / samplesPerSegment;
        final t2 = t * t, t3 = t2 * t;
        out.add(
          (p1 * 2 +
                  (p2 - p0) * t +
                  (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 +
                  (-p0 + p1 * 3 - p2 * 3 + p3) * t3) *
              0.5,
        );
      }
    }
    return out;
  }

  /// The face opening: the detected face oval shrunk slightly towards its
  /// center, or a proportional ellipse if no mesh is available.
  static List<Offset> faceOpening(FaceGeometry face, {double scale = 0.98}) {
    final oval = face.oval;
    if (oval != null && oval.length >= 8) {
      var cx = 0.0, cy = 0.0;
      for (final p in oval) {
        cx += p.dx;
        cy += p.dy;
      }
      final c = Offset(cx / oval.length, cy / oval.length);
      return [for (final p in oval) c + (p - c) * scale];
    }
    final frame = FaceFrame(face);
    return [
      for (var i = 0; i < 48; i++)
        frame.toImage(
          Offset(
            1.0 * scale * math.cos(2 * math.pi * i / 48),
            0.38 + 1.45 * scale * math.sin(2 * math.pi * i / 48),
          ),
        ),
    ];
  }

  /// Fills the outline through [controlPointsImage] minus the face opening.
  static Mask rasterize({
    required List<Offset> controlPointsImage,
    required List<Offset> opening,
    required int width,
    required int height,
  }) {
    final outline = smoothClosed(controlPointsImage);
    final mask = MaskOps.rasterizePolygon(outline, width, height);
    MaskOps.rasterizePolygon(opening, width, height, into: mask, value: 0);
    return mask;
  }
}
