import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Which garment the illustration's window covers.
enum FigureKind { women, hijab, men }

/// Original, abstract figure used across the hook, mode cards and empty
/// states: a featureless head, neck and shoulders, with the garment area
/// either showing a fabric through it or outlined with a dashed cut line.
class FigurePainter extends CustomPainter {
  FigurePainter({
    required this.kind,
    this.fabric,
    this.fabricPhase = 0,
    this.cutProgress = 1,
    this.skin = const Color(0xFFD9B8A0),
    this.photoTint = const Color(0xFFE9E4DD),
    this.garment = const Color(0xFF8E8A85),
  });

  final FigureKind kind;

  /// When set, the window shows this fabric (striped weave).
  final Color? fabric;
  final double fabricPhase;

  /// 0..1: how much of the dashed cut line has been traced.
  final double cutProgress;
  final Color skin;
  final Color photoTint;
  final Color garment;

  Path _head(Size s) => Path()
    ..addOval(Rect.fromCenter(center: Offset(s.width / 2, s.height * 0.36), width: s.width * 0.3, height: s.width * 0.38));

  Path _body(Size s) {
    final w = s.width, h = s.height;
    return Path()
      ..moveTo(w * 0.43, h * 0.52)
      ..lineTo(w * 0.43, h * 0.6)
      ..quadraticBezierTo(w * 0.18, h * 0.64, w * 0.1, h * 0.78)
      ..lineTo(w * 0.06, h)
      ..lineTo(w * 0.94, h)
      ..lineTo(w * 0.9, h * 0.78)
      ..quadraticBezierTo(w * 0.82, h * 0.64, w * 0.57, h * 0.6)
      ..lineTo(w * 0.57, h * 0.52)
      ..close();
  }

  /// The garment window for this kind.
  Path window(Size s) {
    final w = s.width, h = s.height;
    switch (kind) {
      case FigureKind.hijab:
        final outer = Path()
          ..moveTo(w * 0.5, h * 0.13)
          ..cubicTo(w * 0.73, h * 0.13, w * 0.76, h * 0.36, w * 0.71, h * 0.5)
          ..cubicTo(w * 0.7, h * 0.56, w * 0.86, h * 0.6, w * 0.84, h * 0.74)
          ..lineTo(w * 0.16, h * 0.74)
          ..cubicTo(w * 0.14, h * 0.6, w * 0.3, h * 0.56, w * 0.29, h * 0.5)
          ..cubicTo(w * 0.24, h * 0.36, w * 0.27, h * 0.13, w * 0.5, h * 0.13)
          ..close();
        final face = Path()
          ..addOval(Rect.fromCenter(center: Offset(w / 2, h * 0.37), width: w * 0.24, height: w * 0.31));
        return Path.combine(PathOperation.difference, outer, face);
      case FigureKind.women:
        return Path()
          ..moveTo(w * 0.36, h * 0.62)
          ..quadraticBezierTo(w * 0.5, h * 0.7, w * 0.64, h * 0.62)
          ..quadraticBezierTo(w * 0.84, h * 0.66, w * 0.89, h * 0.8)
          ..lineTo(w * 0.92, h)
          ..lineTo(w * 0.08, h)
          ..lineTo(w * 0.11, h * 0.8)
          ..quadraticBezierTo(w * 0.16, h * 0.66, w * 0.36, h * 0.62)
          ..close();
      case FigureKind.men:
        return Path()
          ..moveTo(w * 0.42, h * 0.58)
          ..lineTo(w * 0.5, h * 0.68)
          ..lineTo(w * 0.58, h * 0.58)
          ..quadraticBezierTo(w * 0.84, h * 0.63, w * 0.9, h * 0.78)
          ..lineTo(w * 0.94, h)
          ..lineTo(w * 0.06, h)
          ..lineTo(w * 0.1, h * 0.78)
          ..quadraticBezierTo(w * 0.16, h * 0.63, w * 0.42, h * 0.58)
          ..close();
    }
  }

  static void paintFabric(Canvas canvas, Rect rect, Color color, double phase) {
    canvas.drawRect(rect, Paint()..color = color);
    final hsl = HSLColor.fromColor(color);
    final light = hsl.withLightness((hsl.lightness + 0.08).clamp(0, 1)).toColor();
    final dark = hsl.withLightness((hsl.lightness - 0.07).clamp(0, 1)).toColor();
    final step = rect.width / 18;
    final offset = phase * step * 2;
    final p = Paint()..strokeWidth = step * 0.45;
    for (var x = rect.left - rect.height + offset; x < rect.right + rect.height; x += step) {
      p.color = ((x / step).floor().isEven) ? light : dark;
      canvas.drawLine(Offset(x, rect.bottom), Offset(x + rect.height, rect.top), p);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = photoTint);
    canvas.drawPath(_body(size), Paint()..color = garment);
    canvas.drawPath(_head(size), Paint()..color = skin);
    final neck = Rect.fromLTWH(size.width * 0.44, size.height * 0.5, size.width * 0.12, size.height * 0.1);
    canvas.drawRect(neck, Paint()..color = skin);

    final win = window(size);
    if (fabric != null) {
      canvas.save();
      canvas.clipPath(win);
      paintFabric(canvas, rect, fabric!, fabricPhase);
      canvas.restore();
    } else {
      canvas.drawPath(win, Paint()..color = garment.withValues(alpha: 0.85));
    }
    if (cutProgress > 0) _dashed(canvas, win, cutProgress);
  }

  void _dashed(Canvas canvas, Path path, double progress) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      final end = metric.length * progress.clamp(0.0, 1.0);
      for (var d = 0.0; d < end; d += 9) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 5, end)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(FigurePainter old) =>
      old.kind != kind || old.fabric != fabric || old.fabricPhase != fabricPhase || old.cutProgress != cutProgress;
}

/// Static figure card used on the mode picker.
class ModeArt extends StatelessWidget {
  const ModeArt({required this.kind, super.key});

  final FigureKind kind;

  @override
  Widget build(BuildContext context) {
    final fabric = switch (kind) {
      FigureKind.women => const Color(0xFF6E8B74),
      FigureKind.hijab => const Color(0xFFB98C7B),
      FigureKind.men => const Color(0xFF5E6F8E),
    };
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(painter: FigurePainter(kind: kind, fabric: fabric, cutProgress: 1), size: Size.infinite),
      ),
    );
  }
}

/// Empty state art: a dashed frame and scissors.
class EmptyWindowsArt extends StatelessWidget {
  const EmptyWindowsArt({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return ExcludeSemantics(
      child: SizedBox(
        width: 140,
        height: 140,
        child: CustomPaint(painter: _EmptyPainter(color)),
      ),
    );
  }
}

class _EmptyPainter extends CustomPainter {
  _EmptyPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(14, 10, size.width - 44, size.height - 30), const Radius.circular(14));
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final m in (Path()..addRRect(r)).computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 12) {
        canvas.drawPath(m.extractPath(d, d + 6), p);
      }
    }
    final fig = FigurePainter(kind: FigureKind.women, photoTint: Colors.transparent, garment: color.withValues(alpha: 0.35), skin: color.withValues(alpha: 0.25), cutProgress: 0);
    canvas.save();
    canvas.clipRRect(r);
    canvas.translate(r.left, r.top);
    fig.paint(canvas, r.outerRect.size);
    canvas.restore();
    ScissorsPainter.paintAt(canvas, Offset(size.width - 26, size.height - 26), 24, 0.45, color);
  }

  @override
  bool shouldRepaint(_EmptyPainter old) => old.color != color;
}

/// Simple scissors glyph, drawn so the blades can open and close.
abstract final class ScissorsPainter {
  static void paintAt(Canvas canvas, Offset center, double size, double openAngle, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.09
      ..strokeCap = StrokeCap.round;
    for (final sign in [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(sign * openAngle / 2 - math.pi / 4);
      canvas.drawLine(Offset.zero, Offset(size * 0.62, 0), paint);
      canvas.drawOval(Rect.fromCenter(center: Offset(-size * 0.32, sign * size * 0.1), width: size * 0.42, height: size * 0.3), paint);
      canvas.restore();
    }
    canvas.drawCircle(center, size * 0.05, Paint()..color = color);
  }
}
