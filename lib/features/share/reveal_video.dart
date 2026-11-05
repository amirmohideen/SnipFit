import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

import '../../core/images/image_utils.dart';
import '../../core/platform/native_channels.dart';
import '../../design/illustrations/figure_art.dart';
import '../live_window/compositor.dart';
import 'renderers.dart';
import 'watermark.dart';

/// Everything needed to replay the trend for one capture.
class RevealInputs {
  RevealInputs({
    required this.photo,
    required this.cutout,
    required this.scene,
    required this.affine,
    required this.compositeSize,
    required this.fabricArgb,
    required this.contour,
    required this.watermark,
    required this.texts,
    required this.watermarkCorner,
  });

  /// The original photo (no hole).
  final ui.Image photo;

  /// The photo with the window cut out.
  final ui.Image cutout;

  /// The camera scene behind the window (no cutout).
  final ui.Image scene;

  /// Cutout pixels -> composite pixels: [a, b, c, d, tx, ty].
  final List<double> affine;
  final Size compositeSize;
  final int fabricArgb;

  /// Outer window contour in cutout pixels.
  final List<Offset> contour;
  final bool watermark;
  final ShareTexts texts;
  final Corner watermarkCorner;
}

/// 6.8 seconds, 9:16, 30 fps.
abstract final class RevealVideo {
  static const fps = 30;
  static const seconds = 6.8;
  static const width = 720;
  static const height = 1280;
  static int get frameCount => (fps * seconds).round();

  static Float64List _matrix(List<double> a) => Float64List.fromList([
    a[0], a[1], 0, 0, //
    a[2], a[3], 0, 0, //
    0, 0, 1, 0, //
    a[4], a[5], 0, 1, //
  ]);

  static Offset _apply(List<double> a, Offset p) =>
      Offset(a[0] * p.dx + a[2] * p.dy + a[4], a[1] * p.dx + a[3] * p.dy + a[5]);

  /// Draws frame [t] (seconds) into a [width] x [height] canvas.
  static void drawFrame(ui.Canvas canvas, RevealInputs r, double t, {Path? contourPath}) {
    final frame = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final crop = coverCrop(r.compositeSize, frame.size);
    final s = width / crop.width;
    final m = _matrix(r.affine);
    final paint = Paint()..filterQuality = FilterQuality.high;
    final photoRect = Rect.fromLTWH(0, 0, r.cutout.width.toDouble(), r.cutout.height.toDouble());
    final path = contourPath ?? contourToPath(r.contour);

    canvas.save();
    canvas.scale(s);
    canvas.translate(-crop.left, -crop.top);
    canvas.drawImageRect(
      r.scene,
      Rect.fromLTWH(0, 0, r.scene.width.toDouble(), r.scene.height.toDouble()),
      Offset.zero & r.compositeSize,
      paint,
    );

    double phase(double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
    final appear = Curves.easeOutCubic.transform(phase(0, 0.6));
    final reveal = Curves.easeInOutCubic.transform(phase(3.4, 4.4));
    final dim = 0.38 * (1 - reveal);
    if (dim > 0) {
      canvas.drawRect(Offset.zero & r.compositeSize, Paint()..color = Color.fromRGBO(0, 0, 0, dim));
    }

    canvas.save();
    canvas.transform(m);
    // Printed-photo pop-in.
    final scale = 0.92 + 0.08 * appear;
    canvas.translate(photoRect.center.dx, photoRect.center.dy);
    canvas.scale(scale);
    canvas.translate(-photoRect.center.dx, -photoRect.center.dy);
    final border = (1 - reveal) * appear;
    if (border > 0) {
      canvas.drawRect(
        photoRect.inflate(photoRect.width * 0.025),
        Paint()..color = Color.fromRGBO(255, 255, 255, border),
      );
    }
    if (t < 3.4) {
      canvas.saveLayer(photoRect, Paint()..color = Color.fromRGBO(0, 0, 0, appear));
      canvas.drawImage(r.photo, Offset.zero, paint);
      canvas.restore();
    } else {
      canvas.drawImage(r.cutout, Offset.zero, paint);
      if (reveal < 1) {
        // The window's photo content fades away to reveal the real fabric.
        canvas.saveLayer(photoRect, Paint()..color = Color.fromRGBO(0, 0, 0, 1 - reveal));
        canvas.drawImage(r.photo, Offset.zero, paint);
        canvas.drawImage(r.cutout, Offset.zero, Paint()..blendMode = BlendMode.dstOut);
        canvas.restore();
      }
    }
    // Scissors cut line.
    final trace = phase(1.2, 3.4);
    if (trace > 0 && reveal < 1) {
      final dash = Paint()
        ..color = Color.fromRGBO(255, 255, 255, 1 - reveal)
        ..style = PaintingStyle.stroke
        ..strokeWidth = photoRect.width * 0.006
        ..strokeCap = StrokeCap.round;
      final dashLen = photoRect.width * 0.018;
      for (final metric in path.computeMetrics()) {
        final end = metric.length * trace;
        for (var d = 0.0; d < end; d += dashLen * 1.8) {
          canvas.drawPath(metric.extractPath(d, math.min(d + dashLen, end)), dash);
        }
      }
    }
    canvas.restore();
    canvas.restore();

    // Scissors glyph at the head of the cut, in frame space.
    if (t >= 1.2 && t < 3.4) {
      final metric = path.computeMetrics().firstOrNull;
      final head = metric?.getTangentForOffset(metric.length * phase(1.2, 3.4))?.position;
      if (head != null) {
        final p = (_apply(r.affine, head) - crop.topLeft) * s;
        ScissorsPainter.paintAt(canvas, p, width * 0.07, 0.25 + 0.3 * (0.5 + 0.5 * math.sin(t * 22)), const Color(0xFFFFFFFF));
      }
    }

    // Ending: swatch, hex and the watermark.
    final outro = Curves.easeOutCubic.transform(phase(4.4, 4.9));
    if (outro > 0) {
      canvas.save();
      canvas.translate(0, (1 - outro) * width * 0.08);
      canvas.saveLayer(frame, Paint()..color = Color.fromRGBO(0, 0, 0, outro));
      paintSwatchChip(canvas, Offset(width * 0.04, height - width * 0.05), r.fabricArgb, width * 0.034);
      canvas.restore();
      canvas.restore();
      if (r.watermark) paintWatermark(canvas, frame, r.watermarkCorner, r.texts.watermark);
    }
  }

  static Path contourToPath(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  /// A still frame for the share preview.
  static Future<ui.Image> poster(RevealInputs r, {double t = 2.4}) {
    final rec = ui.PictureRecorder();
    drawFrame(ui.Canvas(rec), r, t);
    return rec.endRecording().toImage(width, height);
  }

  /// Encodes the MP4 with the platform's hardware encoder. Returns false if
  /// the encoder isn't available, so the caller can fall back to an image.
  static Future<bool> encode(RevealInputs r, String path, {void Function(double progress)? onProgress}) async {
    final started = await NativeChannels.videoStart(path: path, width: width, height: height, fps: fps);
    if (!started) return false;
    final contourPath = contourToPath(r.contour);
    try {
      for (var f = 0; f < frameCount; f++) {
        final rec = ui.PictureRecorder();
        drawFrame(ui.Canvas(rec), r, f / fps, contourPath: contourPath);
        final image = await rec.endRecording().toImage(width, height);
        final rgba = await ImageUtils.toRgba(image);
        image.dispose();
        await NativeChannels.videoAddFrame(rgba);
        onProgress?.call((f + 1) / frameCount);
      }
      return await NativeChannels.videoFinish();
    } on Object {
      await NativeChannels.videoCancel();
      rethrow;
    }
  }
}
