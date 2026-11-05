import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../../core/images/image_utils.dart';
import '../cutout_controller.dart';
import '../cutout_isolates.dart';
import '../mask/mask_builder.dart';
import '../mask/mask_ops.dart';
import '../mask/types.dart';

sealed class RefineEdit {
  const RefineEdit();
}

class StrokeEdit extends RefineEdit {
  const StrokeEdit({required this.erase, required this.radius, required this.points});

  final bool erase;
  final double radius;
  final List<ui.Offset> points;
}

class HandlesEdit extends RefineEdit {
  const HandlesEdit(this.handles);

  final List<ui.Offset> handles;
}

class ResetEdit extends RefineEdit {
  const ResetEdit();
}

enum RefineTool { brush, eraser }

/// Edit history over the auto window. Every recompute ends with the
/// no-skin safety pass, so brushing over a face or arm has no effect.
class RefineModel extends ChangeNotifier {
  RefineModel(this.session) : current = session.result.window.copy() {
    _refreshOverlay();
  }

  final CutoutSession session;
  final List<RefineEdit> _edits = [];
  int _cursor = 0;

  Mask current;
  ui.Image? overlay;
  RefineTool tool = RefineTool.brush;
  double brushRadiusScreen = 22;
  int softness = 3;

  bool get canUndo => _cursor > 0;
  bool get canRedo => _cursor < _edits.length;
  bool get isTemplate => session.result.templateControlPoints != null;
  bool get edited => _edits.isNotEmpty;

  Set<String> get toolsUsed => {
    for (final e in _edits.take(_cursor))
      switch (e) {
        StrokeEdit(erase: true) => 'eraser',
        StrokeEdit() => 'brush',
        HandlesEdit() => 'shape',
        ResetEdit() => 'reset',
      },
  };

  /// Template handles as of the current edit position.
  List<ui.Offset>? get handles {
    final initial = session.result.templateControlPoints;
    if (initial == null) return null;
    var h = initial;
    for (final e in _activeEdits) {
      if (e is HandlesEdit) h = e.handles;
    }
    return h;
  }

  Iterable<RefineEdit> get _activeEdits {
    final applied = _edits.take(_cursor).toList();
    final lastReset = applied.lastIndexWhere((e) => e is ResetEdit);
    return applied.skip(lastReset + 1);
  }

  void apply(RefineEdit edit) {
    _edits.removeRange(_cursor, _edits.length);
    _edits.add(edit);
    _cursor++;
    _recompute();
  }

  void undo() {
    if (!canUndo) return;
    _cursor--;
    _recompute();
  }

  void redo() {
    if (!canRedo) return;
    _cursor++;
    _recompute();
  }

  void resetToAuto() => apply(const ResetEdit());

  void setTool(RefineTool t) {
    tool = t;
    notifyListeners();
  }

  void setSoftness(int v) {
    if (v == softness) return;
    softness = v;
    _refreshOverlay();
    notifyListeners();
  }

  void setBrushRadius(double r) {
    brushRadiusScreen = r;
    notifyListeners();
  }

  void _recompute() {
    final skin = session.skin;
    final hs = handles;
    final Mask base;
    if (isTemplate && hs != null) {
      base = MaskBuilder.rasterizeTemplate(handles: hs, opening: session.result.opening!, skin: skin);
    } else {
      base = session.result.window.copy();
    }
    for (final e in _activeEdits) {
      if (e is StrokeEdit) {
        MaskOps.paintStroke(base, e.points, e.radius, e.erase ? 0 : 255);
      }
    }
    current = MaskBuilder.enforceNoSkin(base, skin);
    _refreshOverlay();
    notifyListeners();
  }

  /// Tinted, feathered overlay of the window for display.
  Future<void> _refreshOverlay() async {
    final seq = ++_overlaySeq;
    final m = current;
    final rgba = await tintedOverlayInIsolate(m, softness);
    final image = await ImageUtils.fromRgba(rgba, m.width, m.height);
    if (seq != _overlaySeq || _disposed) {
      image.dispose();
      return;
    }
    overlay?.dispose();
    overlay = image;
    notifyListeners();
  }

  bool _disposed = false;
  int _overlaySeq = 0;

  @override
  void dispose() {
    _disposed = true;
    overlay?.dispose();
    super.dispose();
  }
}
