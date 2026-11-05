import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// A decoded photo held in memory at working resolution.
class DecodedPhoto {
  DecodedPhoto({
    required this.image,
    required this.rgba,
    required this.width,
    required this.height,
  });

  final ui.Image image;
  final Uint8List rgba;
  final int width;
  final int height;

  void dispose() => image.dispose();
}

/// Image helpers. Every export is re-encoded from raw pixels, so no EXIF,
/// GPS location or camera metadata ever survives into a saved or shared file.
abstract final class ImageUtils {
  static const workingMaxSide = 1440;

  /// Decodes (applying orientation) and scales so the long side is at most
  /// [maxSide].
  static Future<DecodedPhoto> decode(Uint8List bytes, {int maxSide = workingMaxSide}) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (w, h) {
        final long = math.max(w, h);
        if (long <= maxSide) return ui.TargetImageSize(width: w, height: h);
        return w >= h
            ? ui.TargetImageSize(width: maxSide)
            : ui.TargetImageSize(height: maxSide);
      },
    );
    var image = (await codec.getNextFrame()).image;
    codec.dispose();
    if (math.max(image.width, image.height) > maxSide * 1.05) {
      final s = maxSide / math.max(image.width, image.height);
      final scaled = await resize(image, (image.width * s).round(), (image.height * s).round());
      image.dispose();
      image = scaled;
    }
    final rgba = await toRgba(image);
    return DecodedPhoto(image: image, rgba: rgba, width: image.width, height: image.height);
  }

  static Future<ui.Image> resize(ui.Image src, int w, int h) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      src,
      ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    return recorder.endRecording().toImage(w, h);
  }

  static Future<Uint8List> toRgba(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  }

  static Future<ui.Image> fromRgba(Uint8List rgba, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, width, height, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }

  static Future<Uint8List> encodePng(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  /// JPEG without any metadata segments, encoded off the UI thread.
  static Future<Uint8List> encodeJpeg(Uint8List rgba, int width, int height, {int quality = 90}) =>
      Isolate.run(() => encodeJpegSync(rgba, width, height, quality: quality));

  static Uint8List encodeJpegSync(Uint8List rgba, int width, int height, {int quality = 90}) {
    final image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      bytesOffset: rgba.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return img.encodeJpg(image, quality: quality);
  }

  static Future<Uint8List> imageToJpeg(ui.Image image, {int quality = 90}) async =>
      encodeJpeg(await toRgba(image), image.width, image.height, quality: quality);

  /// 8-bit luma (Rec. 601) from RGBA.
  static Uint8List luma(Uint8List rgba) {
    final n = rgba.length ~/ 4;
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      final r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2];
      out[i] = (r * 299 + g * 587 + b * 114) ~/ 1000;
    }
    return out;
  }

  /// The photo with the window cut out: alpha = 255 - window alpha.
  /// This stays inside the app; it is never exported as a file.
  static Uint8List cutoutRgba(Uint8List photoRgba, Uint8List windowAlpha) {
    final out = Uint8List.fromList(photoRgba);
    for (var i = 0; i < windowAlpha.length; i++) {
      out[i * 4 + 3] = 255 - windowAlpha[i];
    }
    return out;
  }

  /// True if [jpeg] contains an EXIF (APP1 "Exif") segment.
  static bool hasExif(Uint8List jpeg) {
    var i = 2;
    while (i + 4 < jpeg.length && jpeg[i] == 0xFF) {
      final marker = jpeg[i + 1];
      final len = (jpeg[i + 2] << 8) | jpeg[i + 3];
      if (marker == 0xE1 &&
          i + 10 < jpeg.length &&
          jpeg[i + 4] == 0x45 &&
          jpeg[i + 5] == 0x78 &&
          jpeg[i + 6] == 0x69 &&
          jpeg[i + 7] == 0x66) {
        return true;
      }
      if (marker == 0xDA) break;
      i += 2 + len;
    }
    return false;
  }
}

