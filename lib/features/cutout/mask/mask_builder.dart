import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'hijab_template.dart';
import 'mask_ops.dart';
import 'types.dart';

/// How the window is found.
enum WindowStrategy {
  /// Women and Men modes: the clothes class in the torso region only.
  garment,

  /// Hijab mode, wearing a hijab: hair, clothes and accessory classes in the
  /// head and neck region.
  hijabWorn,

  /// Hijab mode, not wearing one: a hijab-shaped template aligned to the face.
  hijabTemplate,
}

class MaskBuildResult {
  MaskBuildResult({
    required this.window,
    required this.skin,
    required this.quality,
    this.templateControlPoints,
    this.opening,
  });

  /// Binary window: 255 where the live camera shows through.
  final Mask window;

  /// Face and body skin. The window may never include these pixels.
  final Mask skin;

  /// Auto quality score, 0 to 1 (sent to analytics as a number only).
  final double quality;

  /// Editable template handles in image coordinates (template strategy).
  final List<Offset>? templateControlPoints;

  /// Face opening polygon in image coordinates (template strategy).
  final List<Offset>? opening;
}

/// Builds the window mask from segmentation labels and face geometry.
///
/// Safety invariant (hard requirement): the window only ever covers clothing,
/// hair or accessory classes, or the hijab template, and never a face-skin or
/// body-skin pixel. [enforceNoSkin] is applied as the final step of every
/// path, including after manual brush edits.
abstract final class MaskBuilder {
  /// Skin pixels (face + body), grown by one pixel for a safety margin.
  static Mask skinMask(LabelMap labels) {
    final m = Mask(labels.width, labels.height);
    for (var i = 0; i < m.data.length; i++) {
      final c = labels.labels[i];
      if (c == SegClass.faceSkin || c == SegClass.bodySkin) m.data[i] = 255;
    }
    return MaskOps.dilate(m, 1);
  }

  static Mask enforceNoSkin(Mask window, Mask skin) =>
      MaskOps.subtract(window, skin);

  static MaskBuildResult build({
    required LabelMap labels,
    required FaceGeometry face,
    required WindowStrategy strategy,
    HijabStyle style = HijabStyle.classicWrap,
  }) {
    final w = labels.width, h = labels.height;
    final skin = skinMask(labels);
    final frame = FaceFrame(face);
    final scale = math.max(w, h) / 1440;
    int px(double v) => math.max(1, (v * scale).round());

    switch (strategy) {
      case WindowStrategy.hijabTemplate:
        final handles = frame.polygonToImage(HijabTemplate.controlPoints(style));
        final opening = HijabTemplate.faceOpening(face);
        final raw = HijabTemplate.rasterize(
          controlPointsImage: handles,
          opening: opening,
          width: w,
          height: h,
        );
        final window = enforceNoSkin(raw, skin);
        return MaskBuildResult(
          window: window,
          skin: skin,
          quality: _quality(window, labels, face, minArea: 6),
          templateControlPoints: handles,
          opening: opening,
        );

      case WindowStrategy.hijabWorn:
        final region = MaskOps.rasterizePolygon(
          frame.polygonToImage(HijabTemplate.headNeckEnvelope()),
          w,
          h,
        );
        var window = _classes(labels, const {
          SegClass.hair,
          SegClass.clothes,
          SegClass.other,
        });
        window = MaskOps.intersect(window, region);
        // Keep eyes, brows and glasses out: carve the inner face.
        MaskOps.rasterizePolygon(
          HijabTemplate.faceOpening(face, scale: 0.92),
          w,
          h,
          into: window,
          value: 0,
        );
        window = enforceNoSkin(window, skin);
        window = _clean(window, px);
        final ring = _ring(face, w, h);
        window = MaskOps.keepMainComponents(window, minFraction: 0.08, anchor: ring);
        window = enforceNoSkin(window, skin);
        return MaskBuildResult(
          window: window,
          skin: skin,
          quality: _quality(window, labels, face, minArea: 5),
        );

      case WindowStrategy.garment:
        final torso = MaskOps.rasterizePolygon(
          frame.polygonToImage(const [
            Offset(-5.5, 2.2),
            Offset(5.5, 2.2),
            Offset(8, 16),
            Offset(-8, 16),
          ]),
          w,
          h,
        );
        var window = MaskOps.intersect(
          _classes(labels, const {SegClass.clothes}),
          torso,
        );
        window = enforceNoSkin(window, skin);
        window = _clean(window, px);
        final anchor = MaskOps.rasterizePolygon(
          frame.polygonToImage(const [
            Offset(-1.8, 2.4),
            Offset(1.8, 2.4),
            Offset(1.8, 6),
            Offset(-1.8, 6),
          ]),
          w,
          h,
        );
        final anchored = MaskOps.keepMainComponents(
          window,
          minFraction: 0.12,
          anchor: anchor,
        );
        // If nothing touches the chest area (unusual framing), fall back to
        // the largest garment pieces anywhere in the torso region.
        window = anchored.isEmpty
            ? MaskOps.keepMainComponents(window, minFraction: 0.12)
            : anchored;
        window = enforceNoSkin(window, skin);
        return MaskBuildResult(
          window: window,
          skin: skin,
          quality: _quality(window, labels, face, minArea: 8),
        );
    }
  }

  /// Rebuilds a template window after the user moved its handles.
  static Mask rasterizeTemplate({
    required List<Offset> handles,
    required List<Offset> opening,
    required Mask skin,
  }) {
    final raw = HijabTemplate.rasterize(
      controlPointsImage: handles,
      opening: opening,
      width: skin.width,
      height: skin.height,
    );
    return enforceNoSkin(raw, skin);
  }

  static Mask _classes(LabelMap labels, Set<int> classes) {
    final lookup = Uint8List(SegClass.count);
    for (final c in classes) {
      lookup[c] = 255;
    }
    final m = Mask(labels.width, labels.height);
    for (var i = 0; i < m.data.length; i++) {
      m.data[i] = lookup[labels.labels[i]];
    }
    return m;
  }

  /// Small dilate/erode passes: remove specks, close pinholes, fill holes.
  static Mask _clean(Mask m, int Function(double) px) {
    var out = MaskOps.open(m, px(2));
    out = MaskOps.close(out, px(4));
    final holeLimit = (m.width * m.height * 0.002).round();
    return MaskOps.fillHoles(out, holeLimit);
  }

  /// A band just outside the face, used to pick hijab components.
  static Mask _ring(FaceGeometry face, int w, int h) {
    final outer = MaskOps.rasterizePolygon(HijabTemplate.faceOpening(face, scale: 1.45), w, h);
    final inner = MaskOps.rasterizePolygon(HijabTemplate.faceOpening(face, scale: 1.0), w, h);
    return MaskOps.subtract(outer, inner);
  }

  /// Mean class confidence inside the window, discounted when the window is
  /// implausibly small for the face size.
  static double _quality(Mask window, LabelMap labels, FaceGeometry face, {required double minArea}) {
    var n = 0;
    var sum = 0;
    for (var i = 0; i < window.data.length; i++) {
      if (window.data[i] > 127) {
        n++;
        sum += labels.confidence[i];
      }
    }
    if (n == 0) return 0;
    final meanConf = sum / n / 255;
    final unit = math.max(1.0, face.interocular);
    final areaUnits = n / (unit * unit);
    final plausibility = math.min(1.0, areaUnits / minArea);
    return (meanConf * plausibility).clamp(0.0, 1.0);
  }

  /// Guesses whether the person already wears a hijab: around the upper half
  /// of the face, fabric (clothes/accessory classes) outweighs hair.
  static bool detectHijab(LabelMap labels, FaceGeometry face) {
    final w = labels.width, h = labels.height;
    final ring = _ring(face, w, h);
    final eyeY = face.eyeMid.dy;
    var fabric = 0, hair = 0;
    for (var y = 0; y < h && y < eyeY; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        if (ring.data[row + x] == 0) continue;
        final c = labels.labels[row + x];
        if (c == SegClass.clothes || c == SegClass.other) {
          fabric++;
        } else if (c == SegClass.hair) {
          hair++;
        }
      }
    }
    if (fabric + hair < 50) return false;
    return fabric > hair;
  }

  /// Converts a binary window into the final soft alpha (inward feather).
  static Mask finalizeAlpha(Mask window, Mask skin, {required int softness}) {
    final safe = enforceNoSkin(window, skin);
    return MaskOps.featherInward(safe, softness);
  }
}
