import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../core/images/image_utils.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../live_window/compositor.dart';
import 'watermark.dart';

/// Inputs for one capture as rendered into share formats.
class CaptureArt {
  CaptureArt({required this.composite, required this.fabricArgb, required this.windowAlpha});

  final ui.Image composite;
  final int fabricArgb;

  /// Coarse grid (64 wide) of where the fabric shows, 0..255, in composite
  /// space; used to keep the watermark off the fabric.
  final ({Uint8List data, int w, int h})? windowAlpha;
}

class ShareTexts {
  const ShareTexts({required this.watermark, required this.whichOne, required this.aiLabel});

  final String watermark;
  final String whichOne;
  final String aiLabel;
}

TextPainter _text(String s, double size, Color color, {FontWeight weight = FontWeight.w600}) => TextPainter(
  text: TextSpan(
    text: s,
    style: TextStyle(
      fontFamily: SnipTheme.latinFamily,
      fontFamilyFallback: const [SnipTheme.arabicFamily],
      fontSize: size,
      fontWeight: weight,
      color: color,
    ),
  ),
  textDirection: TextDirection.ltr,
)..layout();

void _drawCover(ui.Canvas canvas, ui.Image img, Rect dst, {Radius? radius}) {
  final src = coverCrop(Size(img.width.toDouble(), img.height.toDouble()), dst.size);
  canvas.save();
  if (radius != null) canvas.clipRRect(RRect.fromRectAndRadius(dst, radius));
  canvas.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.high);
  canvas.restore();
}

/// Swatch chip with the hex code, drawn at [origin] (bottom-left anchor).
Rect paintSwatchChip(ui.Canvas canvas, Offset origin, int argb, double unit) {
  final hex = hexOf(argb);
  final tp = _text(hex, unit * 0.9, SnipColors.ink, weight: FontWeight.w600);
  final d = unit * 1.3;
  final pad = unit * 0.55;
  final w = pad + d + pad * 0.7 + tp.width + pad;
  final h = math.max(d, tp.height) + pad * 1.2;
  final r = Rect.fromLTWH(origin.dx, origin.dy - h, w, h);
  canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(h / 2)), Paint()..color = const Color(0xF2FFFFFF));
  final c = Offset(r.left + pad + d / 2, r.center.dy);
  canvas.drawCircle(c, d / 2, Paint()..color = Color(argb));
  canvas.drawCircle(
    c,
    d / 2,
    Paint()
      ..color = const Color(0x22000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1,
  );
  tp.paint(canvas, Offset(c.dx + d / 2 + pad * 0.7, r.center.dy - tp.height / 2));
  return r;
}

/// Single result (9:16): the composite with its swatch and hex code.
Future<ui.Image> renderSingle(CaptureArt art, {required bool watermark, required ShareTexts texts, int width = 1080}) async {
  final height = (width * 16 / 9).round();
  final frame = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  _drawCover(canvas, art.composite, frame);
  final unit = width * 0.034;
  paintSwatchChip(canvas, Offset(width * 0.035, height - width * 0.035), art.fabricArgb, unit);
  if (watermark) {
    final grid = art.windowAlpha;
    final corner = grid == null
        ? Corner.topRight
        : chooseCorner(
            avoid: grid.data,
            gridW: grid.w,
            gridH: grid.h,
            boxW: watermarkBoxFraction.w,
            boxH: watermarkBoxFraction.h,
            blocked: const {Corner.bottomLeft},
          );
    paintWatermark(canvas, frame, corner, texts.watermark);
  }
  return rec.endRecording().toImage(width, height);
}

/// "Which one?" collage of 2-4 captures, in 9:16 or 1:1.
Future<ui.Image> renderCollage(
  List<CaptureArt> arts, {
  required bool watermark,
  required ShareTexts texts,
  bool square = false,
  int width = 1080,
}) async {
  assert(arts.length >= 2 && arts.length <= 4);
  final height = square ? width : (width * 16 / 9).round();
  final frame = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  canvas.drawRect(frame, Paint()..color = SnipColors.paper);

  final margin = width * 0.05;
  final gap = width * 0.025;
  final title = _text(texts.whichOne, width * (square ? 0.06 : 0.075), SnipColors.ink, weight: FontWeight.w700);
  final titleTop = margin * (square ? 0.8 : 1.4);
  title.paint(canvas, Offset((width - title.width) / 2, titleTop));
  final footer = watermark ? width * 0.1 : margin;
  final gridTop = titleTop + title.height + margin * 0.8;
  final gridRect = Rect.fromLTRB(margin, gridTop, width - margin, height - footer);

  final n = arts.length;
  final cols = 2;
  final rows = n <= 2 ? 1 : 2;
  final cellW = (gridRect.width - gap * (cols - 1)) / cols;
  final cellH = (gridRect.height - gap * (rows - 1)) / rows;
  final unit = width * (square ? 0.026 : 0.03);
  for (var i = 0; i < n; i++) {
    final row = i ~/ cols;
    var col = i % cols;
    var left = gridRect.left + col * (cellW + gap);
    // Three items: center the last one.
    if (n == 3 && i == 2) {
      left = gridRect.left + (gridRect.width - cellW) / 2;
      col = 0;
    }
    final cell = Rect.fromLTWH(left, gridRect.top + row * (cellH + gap), cellW, cellH);
    _drawCover(canvas, arts[i].composite, cell, radius: Radius.circular(width * 0.025));
    // Number badge.
    final badge = _text('${i + 1}', unit * 1.1, const Color(0xFFFFFFFF), weight: FontWeight.w700);
    final bc = Offset(cell.left + unit * 1.4, cell.top + unit * 1.4);
    canvas.drawCircle(bc, unit * 1.0, Paint()..color = const Color(0x8C000000));
    badge.paint(canvas, bc - Offset(badge.width / 2, badge.height / 2));
    paintSwatchChip(canvas, Offset(cell.left + unit * 0.6, cell.bottom - unit * 0.6), arts[i].fabricArgb, unit);
  }
  if (watermark) {
    paintWatermark(canvas, Rect.fromLTWH(0, height - footer, width.toDouble(), footer), Corner.bottomRight, texts.watermark, scale: 1.0);
  }
  return rec.endRecording().toImage(width, height);
}

/// Burns a visible "AI-generated" label into an AI image.
Future<ui.Image> renderAiLabeled(ui.Image source, String label) async {
  final w = source.width, h = source.height;
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec)..drawImage(source, Offset.zero, Paint());
  final size = w * 0.032;
  final tp = _text(label, size, const Color(0xFFFFFFFF), weight: FontWeight.w700);
  final pad = size * 0.6;
  final r = Rect.fromLTWH(w * 0.03, w * 0.03, tp.width + pad * 2, tp.height + pad);
  canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(r.height / 2)), Paint()..color = const Color(0xB3000000));
  tp.paint(canvas, Offset(r.left + pad, r.top + pad / 2));
  return rec.endRecording().toImage(w, h);
}

/// JPEG bytes of a rendered image, with no metadata.
Future<Uint8List> toJpeg(ui.Image image, {int quality = 92}) => ImageUtils.imageToJpeg(image, quality: quality);
