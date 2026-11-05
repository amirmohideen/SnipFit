import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/images/image_utils.dart';

/// Where the cutout sits on screen: its center, rotation and on-screen width.
class CutoutPlacement {
  const CutoutPlacement({required this.center, required this.rotation, required this.width});

  final Offset center;
  final double rotation;
  final double width;

  CutoutPlacement copyWith({Offset? center, double? rotation, double? width}) => CutoutPlacement(
    center: center ?? this.center,
    rotation: rotation ?? this.rotation,
    width: width ?? this.width,
  );

  /// Applies this placement to [canvas] so the cutout can be drawn at its
  /// own pixel size with its top-left at the origin.
  void apply(Canvas canvas, ui.Image cutout, {double outputScale = 1}) {
    final k = width / cutout.width;
    canvas.translate(center.dx * outputScale, center.dy * outputScale);
    canvas.rotate(rotation);
    canvas.scale(k * outputScale);
    canvas.translate(-cutout.width / 2, -cutout.height / 2);
  }

  /// Affine [a, b, c, d, tx, ty] mapping cutout pixels to output pixels.
  List<double> affine(ui.Image cutout, double outputScale) {
    final k = width / cutout.width * outputScale;
    final cos = math.cos(rotation) * k, sin = math.sin(rotation) * k;
    final cx = cutout.width / 2, cy = cutout.height / 2;
    final tx = center.dx * outputScale - (cos * cx - sin * cy);
    final ty = center.dy * outputScale - (sin * cx + cos * cy);
    return [cos, sin, -sin, cos, tx, ty];
  }
}

/// Paints the cutout over whatever is behind it (the camera texture).
class CutoutPainter extends CustomPainter {
  CutoutPainter({required this.cutout, required this.placement});

  final ui.Image cutout;
  final CutoutPlacement placement;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    placement.apply(canvas, cutout);
    canvas.drawImage(cutout, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  @override
  bool shouldRepaint(CutoutPainter old) =>
      old.cutout != cutout ||
      old.placement.center != placement.center ||
      old.placement.rotation != placement.rotation ||
      old.placement.width != placement.width;
}

class ComposedCapture {
  ComposedCapture({
    required this.compositeJpeg,
    required this.sceneJpeg,
    required this.width,
    required this.height,
    required this.fabricArgb,
    required this.placement,
  });

  final Uint8List compositeJpeg;
  final Uint8List sceneJpeg;
  final int width;
  final int height;
  final int fabricArgb;
  final List<double> placement;
}

/// Crop of [scene] matching what a BoxFit.cover preview shows on a screen of
/// [screen] size.
Rect coverCrop(Size image, Size screen) {
  final imageAspect = image.width / image.height;
  final screenAspect = screen.width / screen.height;
  if (imageAspect > screenAspect) {
    final w = image.height * screenAspect;
    return Rect.fromLTWH((image.width - w) / 2, 0, w, image.height);
  }
  final h = image.width / screenAspect;
  return Rect.fromLTWH(0, (image.height - h) / 2, image.width, h);
}

/// Renders exactly what the user saw: the camera frame (cropped like the
/// preview) with the cutout on top. Also returns the plain scene and the
/// fabric color sampled through the window.
Future<ComposedCapture> composeCapture({
  required ui.Image scene,
  required ui.Image cutout,
  required CutoutPlacement placement,
  required Size screen,
  int maxWidth = 1080,
}) async {
  final crop = coverCrop(Size(scene.width.toDouble(), scene.height.toDouble()), screen);
  final outW = math.min(maxWidth, crop.width.round());
  final outH = (outW * screen.height / screen.width).round();
  final s = outW / screen.width;
  final out = Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble());
  final paint = Paint()..filterQuality = FilterQuality.high;

  // Scene only.
  final sceneRec = ui.PictureRecorder();
  Canvas(sceneRec).drawImageRect(scene, crop, out, paint);
  final sceneImage = await sceneRec.endRecording().toImage(outW, outH);

  // Composite.
  final compRec = ui.PictureRecorder();
  final comp = Canvas(compRec)..drawImage(sceneImage, Offset.zero, paint);
  comp.save();
  placement.apply(comp, cutout, outputScale: s);
  comp.drawImage(cutout, Offset.zero, paint);
  comp.restore();
  final compositeImage = await compRec.endRecording().toImage(outW, outH);

  final fabric = await sampleWindowColor(scene: sceneImage, cutout: cutout, placement: placement, outputScale: s);

  final compositeJpeg = await ImageUtils.imageToJpeg(compositeImage, quality: 90);
  final sceneJpeg = await ImageUtils.imageToJpeg(sceneImage, quality: 85);
  final affine = placement.affine(cutout, s);
  compositeImage.dispose();
  sceneImage.dispose();
  return ComposedCapture(
    compositeJpeg: compositeJpeg,
    sceneJpeg: sceneJpeg,
    width: outW,
    height: outH,
    fabricArgb: fabric,
    placement: affine,
  );
}

/// Average fabric color seen through the window, ignoring the darkest and
/// brightest 10% (shadows, specular highlights).
Future<int> sampleWindowColor({
  required ui.Image scene,
  required ui.Image cutout,
  required CutoutPlacement placement,
  required double outputScale,
}) async {
  const sample = 0.25;
  final w = math.max(1, (scene.width * sample).round());
  final h = math.max(1, (scene.height * sample).round());
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.scale(sample);
  canvas.saveLayer(Rect.fromLTWH(0, 0, scene.width.toDouble(), scene.height.toDouble()), Paint());
  canvas.save();
  placement.apply(canvas, cutout, outputScale: outputScale);
  final bounds = Rect.fromLTWH(0, 0, cutout.width.toDouble(), cutout.height.toDouble());
  canvas.drawRect(bounds, Paint()..color = const Color(0xFFFFFFFF));
  canvas.drawImage(cutout, Offset.zero, Paint()..blendMode = BlendMode.dstOut);
  canvas.restore();
  canvas.drawImage(scene, Offset.zero, Paint()..blendMode = BlendMode.srcIn);
  canvas.restore();
  final image = await rec.endRecording().toImage(w, h);
  final rgba = await ImageUtils.toRgba(image);
  image.dispose();
  return averageOpaqueColor(rgba);
}

/// Trimmed mean color of pixels with alpha > 200. Returns mid-gray if none.
int averageOpaqueColor(Uint8List rgba) {
  final lumas = <int>[];
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i + 3] > 200) lumas.add(rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114);
  }
  if (lumas.isEmpty) return 0xFF808080;
  final sorted = [...lumas]..sort();
  final lo = sorted[(sorted.length * 0.1).floor()];
  final hi = sorted[math.max(0, (sorted.length * 0.9).ceil() - 1)];
  var r = 0.0, g = 0.0, b = 0.0;
  var n = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i + 3] <= 200) continue;
    final l = rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114;
    if (l < lo || l > hi) continue;
    // Average in linear light for a truer mean.
    r += _toLinear(rgba[i]);
    g += _toLinear(rgba[i + 1]);
    b += _toLinear(rgba[i + 2]);
    n++;
  }
  if (n == 0) return 0xFF808080;
  return 0xFF000000 | (_toSrgb(r / n) << 16) | (_toSrgb(g / n) << 8) | _toSrgb(b / n);
}

double _toLinear(int c) {
  final v = c / 255;
  return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

int _toSrgb(double v) {
  final c = v <= 0.0031308 ? v * 12.92 : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
  return (c * 255).round().clamp(0, 255);
}

String hexOf(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
