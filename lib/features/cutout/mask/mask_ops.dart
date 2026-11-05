import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'types.dart';

/// Fast binary/alpha mask operations in pure Dart, safe to run in isolates.
/// Binary masks use 0 and 255. Borders are replicated, so a garment touching
/// the photo edge is not eaten away by erosion.
abstract final class MaskOps {
  static Mask dilate(Mask m, int r) => _morph(m, r, dilate: true);
  static Mask erode(Mask m, int r) => _morph(m, r, dilate: false);

  /// Removes specks smaller than the radius.
  static Mask open(Mask m, int r) => dilate(erode(m, r), r);

  /// Closes gaps smaller than the radius.
  static Mask close(Mask m, int r) => erode(dilate(m, r), r);

  static Mask _morph(Mask m, int r, {required bool dilate}) {
    if (r <= 0) return m.copy();
    final w = m.width, h = m.height;
    final tmp = Uint8List(w * h);
    final out = Uint8List(w * h);
    final window = 2 * r + 1;
    // Horizontal pass: running count of set pixels in [x-r, x+r].
    for (var y = 0; y < h; y++) {
      final row = y * w;
      var count = 0;
      for (var k = -r; k <= r; k++) {
        if (m.data[row + k.clamp(0, w - 1)] > 127) count++;
      }
      for (var x = 0; x < w; x++) {
        tmp[row + x] = (dilate ? count > 0 : count == window) ? 255 : 0;
        final outIdx = (x - r).clamp(0, w - 1);
        final inIdx = (x + r + 1).clamp(0, w - 1);
        if (m.data[row + outIdx] > 127) count--;
        if (m.data[row + inIdx] > 127) count++;
      }
    }
    // Vertical pass.
    for (var x = 0; x < w; x++) {
      var count = 0;
      for (var k = -r; k <= r; k++) {
        if (tmp[k.clamp(0, h - 1) * w + x] > 127) count++;
      }
      for (var y = 0; y < h; y++) {
        out[y * w + x] = (dilate ? count > 0 : count == window) ? 255 : 0;
        final outIdx = (y - r).clamp(0, h - 1);
        final inIdx = (y + r + 1).clamp(0, h - 1);
        if (tmp[outIdx * w + x] > 127) count--;
        if (tmp[inIdx * w + x] > 127) count++;
      }
    }
    return Mask(w, h, out);
  }

  /// Separable box blur with replicated borders.
  static Mask boxBlur(Mask m, int r) {
    if (r <= 0) return m.copy();
    final w = m.width, h = m.height;
    final tmp = Uint16List(w * h);
    final out = Uint8List(w * h);
    final window = 2 * r + 1;
    for (var y = 0; y < h; y++) {
      final row = y * w;
      var sum = 0;
      for (var k = -r; k <= r; k++) {
        sum += m.data[row + k.clamp(0, w - 1)];
      }
      for (var x = 0; x < w; x++) {
        tmp[row + x] = sum ~/ window;
        sum -= m.data[row + (x - r).clamp(0, w - 1)];
        sum += m.data[row + (x + r + 1).clamp(0, w - 1)];
      }
    }
    for (var x = 0; x < w; x++) {
      var sum = 0;
      for (var k = -r; k <= r; k++) {
        sum += tmp[k.clamp(0, h - 1) * w + x];
      }
      for (var y = 0; y < h; y++) {
        out[y * w + x] = sum ~/ window;
        sum -= tmp[(y - r).clamp(0, h - 1) * w + x];
        sum += tmp[(y + r + 1).clamp(0, h - 1) * w + x];
      }
    }
    return Mask(w, h, out);
  }

  /// Soft edge that only ever fades inward: alpha ramps from 0 at the window
  /// edge to fully open [r] pixels inside it, and is exactly zero wherever the
  /// binary mask is zero, so feathering can never spill onto skin.
  static Mask featherInward(Mask binary, int r) {
    if (r <= 0) return binary.copy();
    final dist = distanceInside(binary);
    final out = Uint8List(binary.width * binary.height);
    for (var i = 0; i < out.length; i++) {
      if (binary.data[i] <= 127) continue;
      final t = ((dist[i] - 0.5) / r).clamp(0.0, 1.0);
      out[i] = (t * t * (3 - 2 * t) * 255).round();
    }
    return Mask(binary.width, binary.height, out);
  }

  /// Approximate Euclidean distance (two-pass chamfer) from each set pixel to
  /// the nearest unset pixel. Image borders don't count as edges, so a
  /// garment running off the photo isn't faded at the frame.
  static Float32List distanceInside(Mask m) {
    final w = m.width, h = m.height;
    const inf = 1e9;
    const diag = 1.41421356;
    final d = Float32List(w * h);
    for (var i = 0; i < d.length; i++) {
      d[i] = m.data[i] > 127 ? inf : 0;
    }
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        var v = d[i];
        if (v == 0) continue;
        if (x > 0 && d[i - 1] + 1 < v) v = d[i - 1] + 1;
        if (y > 0) {
          if (d[i - w] + 1 < v) v = d[i - w] + 1;
          if (x > 0 && d[i - w - 1] + diag < v) v = d[i - w - 1] + diag;
          if (x < w - 1 && d[i - w + 1] + diag < v) v = d[i - w + 1] + diag;
        }
        d[i] = v;
      }
    }
    for (var y = h - 1; y >= 0; y--) {
      for (var x = w - 1; x >= 0; x--) {
        final i = y * w + x;
        var v = d[i];
        if (v == 0) continue;
        if (x < w - 1 && d[i + 1] + 1 < v) v = d[i + 1] + 1;
        if (y < h - 1) {
          if (d[i + w] + 1 < v) v = d[i + w] + 1;
          if (x < w - 1 && d[i + w + 1] + diag < v) v = d[i + w + 1] + diag;
          if (x > 0 && d[i + w - 1] + diag < v) v = d[i + w - 1] + diag;
        }
        d[i] = v;
      }
    }
    return d;
  }

  static Mask subtract(Mask a, Mask b) {
    final out = Uint8List(a.data.length);
    for (var i = 0; i < out.length; i++) {
      out[i] = b.data[i] > 127 ? 0 : a.data[i];
    }
    return Mask(a.width, a.height, out);
  }

  static Mask intersect(Mask a, Mask b) {
    final out = Uint8List(a.data.length);
    for (var i = 0; i < out.length; i++) {
      out[i] = (a.data[i] > 127 && b.data[i] > 127) ? 255 : 0;
    }
    return Mask(a.width, a.height, out);
  }

  static Mask union(Mask a, Mask b) {
    final out = Uint8List(a.data.length);
    for (var i = 0; i < out.length; i++) {
      out[i] = (a.data[i] > 127 || b.data[i] > 127) ? 255 : 0;
    }
    return Mask(a.width, a.height, out);
  }

  /// 4-connected component labels (0 = unset) and the area of each label.
  static ({Int32List labels, List<int> areas}) components(Mask m) {
    final w = m.width, h = m.height;
    final labels = Int32List(w * h);
    final areas = <int>[0];
    final stack = Int32List(w * h);
    var next = 1;
    for (var i = 0; i < labels.length; i++) {
      if (m.data[i] <= 127 || labels[i] != 0) continue;
      var top = 0;
      stack[top++] = i;
      labels[i] = next;
      var area = 0;
      while (top > 0) {
        final p = stack[--top];
        area++;
        final x = p % w;
        final y = p ~/ w;
        if (x > 0) {
          final q = p - 1;
          if (m.data[q] > 127 && labels[q] == 0) {
            labels[q] = next;
            stack[top++] = q;
          }
        }
        if (x < w - 1) {
          final q = p + 1;
          if (m.data[q] > 127 && labels[q] == 0) {
            labels[q] = next;
            stack[top++] = q;
          }
        }
        if (y > 0) {
          final q = p - w;
          if (m.data[q] > 127 && labels[q] == 0) {
            labels[q] = next;
            stack[top++] = q;
          }
        }
        if (y < h - 1) {
          final q = p + w;
          if (m.data[q] > 127 && labels[q] == 0) {
            labels[q] = next;
            stack[top++] = q;
          }
        }
      }
      areas.add(area);
      next++;
    }
    return (labels: labels, areas: areas);
  }

  /// Keeps components whose area is at least [minFraction] of the largest
  /// one. If [anchor] is given, only components overlapping it are kept.
  static Mask keepMainComponents(Mask m, {double minFraction = 0.1, Mask? anchor}) {
    final cc = components(m);
    if (cc.areas.length <= 1) return m.copy();
    final touches = List<bool>.filled(cc.areas.length, anchor == null);
    if (anchor != null) {
      for (var i = 0; i < cc.labels.length; i++) {
        final l = cc.labels[i];
        if (l != 0 && anchor.data[i] > 127) touches[l] = true;
      }
    }
    var largest = 0;
    for (var l = 1; l < cc.areas.length; l++) {
      if (touches[l] && cc.areas[l] > largest) largest = cc.areas[l];
    }
    if (largest == 0) return Mask(m.width, m.height);
    final keep = List<bool>.generate(
      cc.areas.length,
      (l) => l != 0 && touches[l] && cc.areas[l] >= largest * minFraction,
    );
    final out = Uint8List(m.data.length);
    for (var i = 0; i < out.length; i++) {
      if (keep[cc.labels[i]]) out[i] = 255;
    }
    return Mask(m.width, m.height, out);
  }

  /// Fills enclosed holes smaller than [maxHoleArea] pixels.
  static Mask fillHoles(Mask m, int maxHoleArea) {
    final w = m.width, h = m.height;
    final inverted = Mask(w, h);
    for (var i = 0; i < m.data.length; i++) {
      inverted.data[i] = m.data[i] > 127 ? 0 : 255;
    }
    final cc = components(inverted);
    final touchesBorder = List<bool>.filled(cc.areas.length, false);
    for (var x = 0; x < w; x++) {
      touchesBorder[cc.labels[x]] = true;
      touchesBorder[cc.labels[(h - 1) * w + x]] = true;
    }
    for (var y = 0; y < h; y++) {
      touchesBorder[cc.labels[y * w]] = true;
      touchesBorder[cc.labels[y * w + w - 1]] = true;
    }
    final out = Uint8List.fromList(m.data);
    for (var i = 0; i < out.length; i++) {
      final l = cc.labels[i];
      if (l != 0 && !touchesBorder[l] && cc.areas[l] <= maxHoleArea) {
        out[i] = 255;
      }
    }
    return Mask(w, h, out);
  }

  /// Even-odd scanline fill of a closed polygon, sampled at pixel centers.
  static Mask rasterizePolygon(List<Offset> poly, int w, int h, {Mask? into, int value = 255}) {
    final out = into ?? Mask(w, h);
    if (poly.length < 3) return out;
    var minY = double.infinity, maxY = double.negativeInfinity;
    for (final p in poly) {
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final y0 = math.max(0, minY.floor());
    final y1 = math.min(h - 1, maxY.ceil());
    final xs = <double>[];
    for (var y = y0; y <= y1; y++) {
      final sy = y + 0.5;
      xs.clear();
      for (var i = 0; i < poly.length; i++) {
        final a = poly[i];
        final b = poly[(i + 1) % poly.length];
        if ((a.dy <= sy && b.dy > sy) || (b.dy <= sy && a.dy > sy)) {
          xs.add(a.dx + (sy - a.dy) / (b.dy - a.dy) * (b.dx - a.dx));
        }
      }
      xs.sort();
      for (var k = 0; k + 1 < xs.length; k += 2) {
        final xa = math.max(0, (xs[k] - 0.5).ceil());
        final xb = math.min(w - 1, (xs[k + 1] - 0.5).floor());
        final row = y * w;
        for (var x = xa; x <= xb; x++) {
          out.data[row + x] = value;
        }
      }
    }
    return out;
  }

  /// Paints a filled disc.
  static void paintDisc(Mask m, double cx, double cy, double r, int value) {
    final x0 = math.max(0, (cx - r).floor());
    final x1 = math.min(m.width - 1, (cx + r).ceil());
    final y0 = math.max(0, (cy - r).floor());
    final y1 = math.min(m.height - 1, (cy + r).ceil());
    final r2 = r * r;
    for (var y = y0; y <= y1; y++) {
      final dy = y + 0.5 - cy;
      final row = y * m.width;
      for (var x = x0; x <= x1; x++) {
        final dx = x + 0.5 - cx;
        if (dx * dx + dy * dy <= r2) m.data[row + x] = value;
      }
    }
  }

  /// Paints a brush stroke as overlapping discs along the path.
  static void paintStroke(Mask m, List<Offset> points, double r, int value) {
    if (points.isEmpty) return;
    final step = math.max(1.0, r / 3);
    paintDisc(m, points.first.dx, points.first.dy, r, value);
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final d = (b - a).distance;
      final n = math.max(1, (d / step).ceil());
      for (var k = 1; k <= n; k++) {
        final p = Offset.lerp(a, b, k / n)!;
        paintDisc(m, p.dx, p.dy, r, value);
      }
    }
  }
}
