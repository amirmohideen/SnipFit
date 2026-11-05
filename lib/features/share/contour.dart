import 'dart:typed_data';
import 'dart:ui' show Offset;

/// Traces the outer boundary of the largest set region in a binary grid
/// (Moore-neighbour tracing). Used to draw the scissors' cut line in the
/// reveal video. Returns points in grid coordinates, simplified.
List<Offset> traceOuterContour(Uint8List grid, int w, int h, {int maxPoints = 400}) {
  // Largest component via flood fill.
  final labels = Int32List(w * h);
  var bestLabel = 0, bestArea = 0, next = 1;
  final stack = Int32List(w * h);
  for (var i = 0; i < grid.length; i++) {
    if (grid[i] == 0 || labels[i] != 0) continue;
    var top = 0, area = 0;
    stack[top++] = i;
    labels[i] = next;
    while (top > 0) {
      final p = stack[--top];
      area++;
      final x = p % w, y = p ~/ w;
      for (final q in [if (x > 0) p - 1, if (x < w - 1) p + 1, if (y > 0) p - w, if (y < h - 1) p + w]) {
        if (grid[q] != 0 && labels[q] == 0) {
          labels[q] = next;
          stack[top++] = q;
        }
      }
    }
    if (area > bestArea) {
      bestArea = area;
      bestLabel = next;
    }
    next++;
  }
  if (bestLabel == 0) return const [];
  bool inside(int x, int y) => x >= 0 && y >= 0 && x < w && y < h && labels[y * w + x] == bestLabel;

  // Start at the top-most, left-most pixel of the component.
  var start = -1;
  for (var i = 0; i < labels.length; i++) {
    if (labels[i] == bestLabel) {
      start = i;
      break;
    }
  }
  final sx = start % w, sy = start ~/ w;
  // Clockwise neighbours starting from west.
  const dx = [-1, -1, 0, 1, 1, 1, 0, -1];
  const dy = [0, -1, -1, -1, 0, 1, 1, 1];
  final points = <Offset>[Offset(sx.toDouble(), sy.toDouble())];
  var cx = sx, cy = sy;
  var dir = 0; // came from the west
  final limit = w * h * 2;
  for (var steps = 0; steps < limit; steps++) {
    var found = false;
    for (var k = 0; k < 8; k++) {
      final d = (dir + k) % 8;
      final nx = cx + dx[d], ny = cy + dy[d];
      if (inside(nx, ny)) {
        cx = nx;
        cy = ny;
        dir = (d + 6) % 8; // backtrack: start search from the left of the move
        found = true;
        break;
      }
    }
    if (!found) break;
    if (cx == sx && cy == sy) break;
    points.add(Offset(cx.toDouble(), cy.toDouble()));
  }
  if (points.length <= maxPoints) return points;
  final step = points.length / maxPoints;
  return [for (var i = 0.0; i < points.length; i += step) points[i.floor()]];
}
