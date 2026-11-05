import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../design/illustrations/figure_art.dart';
import '../../design/theme.dart';

enum Corner { bottomRight, bottomLeft, topRight, topLeft }

/// Picks the corner whose watermark box overlaps the least with [avoid]
/// (a coarse occupancy grid of fabric/face pixels). Ties prefer the order of
/// [Corner.values]. [blocked] corners (e.g. where the swatch chip sits) are
/// skipped.
Corner chooseCorner({
  required Uint8List avoid,
  required int gridW,
  required int gridH,
  required double boxW,
  required double boxH,
  Set<Corner> blocked = const {},
}) {
  var best = Corner.bottomRight;
  var bestScore = double.infinity;
  for (final c in Corner.values) {
    if (blocked.contains(c)) continue;
    final x0 = (c == Corner.bottomLeft || c == Corner.topLeft) ? 0 : ((1 - boxW) * gridW).floor();
    final y0 = (c == Corner.topLeft || c == Corner.topRight) ? 0 : ((1 - boxH) * gridH).floor();
    final x1 = math.min(gridW, x0 + (boxW * gridW).ceil());
    final y1 = math.min(gridH, y0 + (boxH * gridH).ceil());
    var score = 0.0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        score += avoid[y * gridW + x];
      }
    }
    if (score < bestScore - 1e-6) {
      bestScore = score;
      best = c;
    }
  }
  return best;
}

/// The small "Made with Snipfit" mark. Removing it is a Pro perk.
void paintWatermark(ui.Canvas canvas, ui.Rect frame, Corner corner, String label, {double scale = 1}) {
  final fontSize = frame.width * 0.028 * scale;
  final tp = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        fontFamily: SnipTheme.latinFamily,
        fontFamilyFallback: const [SnipTheme.arabicFamily],
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: const Color(0xFFFFFFFF),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final pad = fontSize * 0.6;
  final icon = fontSize * 1.1;
  final w = icon + pad * 0.6 + tp.width + pad * 2;
  final h = math.max(tp.height, icon) + pad * 1.2;
  final margin = frame.width * 0.035;
  final left = (corner == Corner.bottomLeft || corner == Corner.topLeft) ? frame.left + margin : frame.right - margin - w;
  final top = (corner == Corner.topLeft || corner == Corner.topRight) ? frame.top + margin : frame.bottom - margin - h;
  final box = RRect.fromRectAndRadius(Rect.fromLTWH(left, top, w, h), Radius.circular(h / 2));
  canvas.drawRRect(box, Paint()..color = const Color(0x8C000000));
  ScissorsPainter.paintAt(canvas, Offset(left + pad + icon / 2, top + h / 2), icon, 0.5, const Color(0xFFFFFFFF));
  tp.paint(canvas, Offset(left + pad + icon + pad * 0.6, top + (h - tp.height) / 2));
}

/// Watermark size as a fraction of the frame, for corner scoring.
const watermarkBoxFraction = (w: 0.42, h: 0.07);
