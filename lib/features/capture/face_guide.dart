import 'package:flutter/material.dart';

/// Face-and-shoulders outline: a soft scrim with the silhouette left clear.
class FaceGuidePainter extends CustomPainter {
  const FaceGuidePainter();

  static Path silhouette(Size size) {
    final w = size.width, h = size.height;
    final cx = w / 2;
    final headW = w * 0.46, headH = headW * 1.3;
    final headTop = h * 0.19;
    final head = Rect.fromCenter(center: Offset(cx, headTop + headH / 2), width: headW, height: headH);
    final neckY = head.bottom - headH * 0.04;
    final shoulderY = neckY + h * 0.07;
    final path = Path()..addOval(head);
    final body = Path()
      ..moveTo(cx - headW * 0.24, neckY)
      ..lineTo(cx - headW * 0.26, shoulderY - h * 0.025)
      ..quadraticBezierTo(cx - w * 0.36, shoulderY, cx - w * 0.46, shoulderY + h * 0.09)
      ..lineTo(cx - w * 0.5, h * 0.80)
      ..lineTo(cx + w * 0.5, h * 0.80)
      ..lineTo(cx + w * 0.46, shoulderY + h * 0.09)
      ..quadraticBezierTo(cx + w * 0.36, shoulderY, cx + headW * 0.26, shoulderY - h * 0.025)
      ..lineTo(cx + headW * 0.24, neckY)
      ..close();
    return Path.combine(PathOperation.union, path, body);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final guide = silhouette(size);
    final scrim = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), guide);
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: 0.32));
    canvas.drawPath(
      guide,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(FaceGuidePainter oldDelegate) => false;
}
