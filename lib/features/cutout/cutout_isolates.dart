import 'dart:isolate';
import 'dart:typed_data';

import '../../core/images/image_utils.dart';
import 'mask/hijab_template.dart';
import 'mask/label_map.dart';
import 'mask/mask_builder.dart';
import 'mask/mask_ops.dart';
import 'mask/types.dart';

// Top-level helpers so isolate closures only ever capture plain data.

Future<LabelMap> upsampleLabelsInIsolate(ClassProbabilities p, int w, int h) =>
    Isolate.run(() => upsampleLabels(p, w, h));

Future<MaskBuildResult> buildMaskInIsolate({
  required LabelMap labels,
  required FaceGeometry face,
  required WindowStrategy strategy,
  required HijabStyle style,
}) => Isolate.run(() => MaskBuilder.build(labels: labels, face: face, strategy: strategy, style: style));

Future<Mask> finalizeAlphaInIsolate(Mask window, Mask skin, int softness) =>
    Isolate.run(() => MaskBuilder.finalizeAlpha(window, skin, softness: softness));

Future<Uint8List> cutoutRgbaInIsolate(Uint8List photoRgba, Uint8List alpha) =>
    Isolate.run(() => ImageUtils.cutoutRgba(photoRgba, alpha));

/// A small preview: the cutout over a neutral checker so the window reads as
/// a hole.
Future<Uint8List> windowThumbnailInIsolate(Uint8List cutoutRgba, int w, int h) => Isolate.run(() {
  const target = 360;
  final scale = target / (w > h ? w : h);
  final tw = (w * scale).round(), th = (h * scale).round();
  final out = Uint8List(tw * th * 4);
  for (var y = 0; y < th; y++) {
    final sy = (y / scale).floor().clamp(0, h - 1);
    for (var x = 0; x < tw; x++) {
      final sx = (x / scale).floor().clamp(0, w - 1);
      final si = (sy * w + sx) * 4;
      final a = cutoutRgba[si + 3];
      final checker = ((x ~/ 12) + (y ~/ 12)).isEven ? 236 : 222;
      final di = (y * tw + x) * 4;
      for (var c = 0; c < 3; c++) {
        out[di + c] = (cutoutRgba[si + c] * a + checker * (255 - a)) ~/ 255;
      }
      out[di + 3] = 255;
    }
  }
  return ImageUtils.encodeJpegSync(out, tw, th, quality: 82);
});

/// Tinted RGBA overlay of the (feathered) window for the Refine screen.
Future<Uint8List> tintedOverlayInIsolate(Mask window, int softness) => Isolate.run(() {
  final soft = softness > 0 ? MaskOps.featherInward(window, softness) : window;
  final rgba = Uint8List(window.width * window.height * 4);
  for (var i = 0; i < soft.data.length; i++) {
    final a = soft.data[i];
    if (a == 0) continue;
    rgba[i * 4] = 0xB0;
    rgba[i * 4 + 1] = 0x4A;
    rgba[i * 4 + 2] = 0x33;
    rgba[i * 4 + 3] = (a * 150) ~/ 255;
  }
  return rgba;
});
