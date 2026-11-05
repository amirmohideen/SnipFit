import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../design/tokens.dart';
import 'refine_model.dart';

/// The editable photo: one finger paints or erases (or drags a template
/// handle), two fingers zoom and pan.
class RefineCanvas extends StatefulWidget {
  const RefineCanvas({required this.model, required this.semanticLabel, super.key});

  final RefineModel model;
  final String semanticLabel;

  @override
  State<RefineCanvas> createState() => _RefineCanvasState();
}

class _RefineCanvasState extends State<RefineCanvas> {
  double _userScale = 1;
  Offset _userOffset = Offset.zero;
  double _startScale = 1;
  Offset _startFocal = Offset.zero;
  Offset _startOffset = Offset.zero;

  List<Offset>? _stroke;
  int? _dragHandle;
  List<Offset>? _dragHandles;
  bool _multiTouch = false;

  late Size _size;

  RefineModel get model => widget.model;

  ({double scale, Offset offset}) get _fit {
    final img = model.session.photo;
    final s = math.min(_size.width / img.width, _size.height / img.height);
    final off = Offset((_size.width - img.width * s) / 2, (_size.height - img.height * s) / 2);
    return (scale: s, offset: off);
  }

  double get _totalScale => _fit.scale * _userScale;

  Offset _toImage(Offset screen) {
    final fit = _fit;
    final p = (screen - _userOffset) / _userScale;
    return (p - fit.offset) / fit.scale;
  }

  Offset _toScreen(Offset image) {
    final fit = _fit;
    return (image * fit.scale + fit.offset) * _userScale + _userOffset;
  }

  int? _hitHandle(Offset screen) {
    final hs = model.handles;
    if (hs == null) return null;
    for (var i = 0; i < hs.length; i++) {
      if ((_toScreen(hs[i]) - screen).distance < 28) return i;
    }
    return null;
  }

  void _onScaleStart(ScaleStartDetails d) {
    _multiTouch = d.pointerCount > 1;
    _startScale = _userScale;
    _startFocal = d.localFocalPoint;
    _startOffset = _userOffset;
    if (_multiTouch) return;
    final hit = _hitHandle(d.localFocalPoint);
    if (hit != null) {
      _dragHandle = hit;
      _dragHandles = [...model.handles!];
    } else {
      _stroke = [_toImage(d.localFocalPoint)];
    }
    setState(() {});
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount > 1 && !_multiTouch) {
      // A second finger arrived: cancel any stroke and switch to zoom.
      _multiTouch = true;
      _stroke = null;
      _dragHandle = null;
      _startScale = _userScale;
      _startFocal = d.localFocalPoint;
      _startOffset = _userOffset;
    }
    if (_multiTouch) {
      final newScale = (_startScale * d.scale).clamp(1.0, 6.0);
      final focalImage = (_startFocal - _startOffset) / _startScale;
      setState(() {
        _userScale = newScale;
        _userOffset = d.localFocalPoint - focalImage * newScale;
      });
      return;
    }
    if (_dragHandle != null) {
      setState(() => _dragHandles![_dragHandle!] = _toImage(d.localFocalPoint));
      return;
    }
    if (_stroke != null) {
      setState(() => _stroke!.add(_toImage(d.localFocalPoint)));
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_dragHandle != null && _dragHandles != null) {
      model.apply(HandlesEdit(List.unmodifiable(_dragHandles!)));
    } else if (_stroke != null && _stroke!.isNotEmpty) {
      model.apply(
        StrokeEdit(
          erase: model.tool == RefineTool.eraser,
          radius: model.brushRadiusScreen / _totalScale,
          points: List.unmodifiable(_stroke!),
        ),
      );
    }
    setState(() {
      _stroke = null;
      _dragHandle = null;
      _dragHandles = null;
      if (_userScale <= 1.01) {
        _userScale = 1;
        _userOffset = Offset.zero;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        return Semantics(
          label: widget.semanticLabel,
          image: true,
          child: GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: ListenableBuilder(
              listenable: model,
              builder: (context, _) => CustomPaint(
                size: _size,
                painter: _RefinePainter(
                  photo: model.session.photo.image,
                  overlay: model.overlay,
                  fitScale: _fit.scale,
                  fitOffset: _fit.offset,
                  userScale: _userScale,
                  userOffset: _userOffset,
                  stroke: _stroke,
                  strokeRadius: model.brushRadiusScreen / _totalScale,
                  erasing: model.tool == RefineTool.eraser,
                  handles: _dragHandles ?? model.handles,
                  activeHandle: _dragHandle,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RefinePainter extends CustomPainter {
  _RefinePainter({
    required this.photo,
    required this.overlay,
    required this.fitScale,
    required this.fitOffset,
    required this.userScale,
    required this.userOffset,
    required this.stroke,
    required this.strokeRadius,
    required this.erasing,
    required this.handles,
    required this.activeHandle,
  });

  final ui.Image photo;
  final ui.Image? overlay;
  final double fitScale;
  final Offset fitOffset;
  final double userScale;
  final Offset userOffset;
  final List<Offset>? stroke;
  final double strokeRadius;
  final bool erasing;
  final List<Offset>? handles;
  final int? activeHandle;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(userOffset.dx, userOffset.dy);
    canvas.scale(userScale);
    canvas.translate(fitOffset.dx, fitOffset.dy);
    canvas.scale(fitScale);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    canvas.drawImage(photo, Offset.zero, paint);
    if (overlay != null) canvas.drawImage(overlay!, Offset.zero, paint);

    if (stroke != null) {
      final p = Paint()
        ..color = erasing ? Colors.white.withValues(alpha: 0.55) : SnipColors.accent.withValues(alpha: 0.55)
        ..strokeWidth = strokeRadius * 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(stroke!.first.dx, stroke!.first.dy);
      for (final q in stroke!.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      if (stroke!.length == 1) {
        canvas.drawCircle(stroke!.first, strokeRadius, p..style = PaintingStyle.fill);
      } else {
        canvas.drawPath(path, p);
      }
    }

    if (handles != null) {
      final total = fitScale * userScale;
      final outline = Path();
      final pts = handles!;
      outline.moveTo(pts.first.dx, pts.first.dy);
      for (final q in pts.skip(1)) {
        outline.lineTo(q.dx, q.dy);
      }
      outline.close();
      canvas.drawPath(
        outline,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 / total,
      );
      for (var i = 0; i < pts.length; i++) {
        final r = (i == activeHandle ? 11 : 8) / total;
        canvas.drawCircle(pts[i], r, Paint()..color = Colors.white);
        canvas.drawCircle(
          pts[i],
          r,
          Paint()
            ..color = SnipColors.ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 / total,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RefinePainter old) => true;
}
