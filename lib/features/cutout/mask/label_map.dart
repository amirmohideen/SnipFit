import 'dart:typed_data';

import 'types.dart';

/// Upsamples the segmenter's class probabilities (256x256, letterboxed) to
/// the working photo size and takes the most likely class per pixel.
///
/// Interpolating probabilities before the argmax gives much smoother edges
/// than upscaling a hard label map.
LabelMap upsampleLabels(ClassProbabilities p, int outW, int outH) {
  final labels = Uint8List(outW * outH);
  final confidence = Uint8List(outW * outH);
  final mw = p.width, mh = p.height;
  final x0 = p.padLeft * mw;
  final x1 = (1 - p.padRight) * mw;
  final y0 = p.padTop * mh;
  final y1 = (1 - p.padBottom) * mh;
  final sx = (x1 - x0) / outW;
  final sy = (y1 - y0) / outH;
  const c = SegClass.count;
  final data = p.data;
  final probs = Float64List(c);

  for (var y = 0; y < outH; y++) {
    final fy = (y0 + (y + 0.5) * sy - 0.5).clamp(0.0, mh - 1.0);
    final iy0 = fy.floor();
    final iy1 = iy0 + 1 < mh ? iy0 + 1 : iy0;
    final ty = fy - iy0;
    for (var x = 0; x < outW; x++) {
      final fx = (x0 + (x + 0.5) * sx - 0.5).clamp(0.0, mw - 1.0);
      final ix0 = fx.floor();
      final ix1 = ix0 + 1 < mw ? ix0 + 1 : ix0;
      final tx = fx - ix0;
      final w00 = (1 - tx) * (1 - ty);
      final w10 = tx * (1 - ty);
      final w01 = (1 - tx) * ty;
      final w11 = tx * ty;
      final b00 = (iy0 * mw + ix0) * c;
      final b10 = (iy0 * mw + ix1) * c;
      final b01 = (iy1 * mw + ix0) * c;
      final b11 = (iy1 * mw + ix1) * c;
      var best = 0;
      var bestP = -1.0;
      for (var k = 0; k < c; k++) {
        final v = data[b00 + k] * w00 +
            data[b10 + k] * w10 +
            data[b01 + k] * w01 +
            data[b11 + k] * w11;
        probs[k] = v;
        if (v > bestP) {
          bestP = v;
          best = k;
        }
      }
      final i = y * outW + x;
      labels[i] = best;
      confidence[i] = (bestP.clamp(0.0, 1.0) * 255).round();
    }
  }
  return LabelMap(
    width: outW,
    height: outH,
    labels: labels,
    confidence: confidence,
  );
}
