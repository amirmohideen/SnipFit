import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/images/image_utils.dart';
import '../../core/images/provenance.dart';
import '../../core/storage/media_store.dart';
import '../../design/widgets/common.dart';
import '../../l10n/l10n.dart';
import '../paywall/entitlements.dart';
import 'contour.dart';
import 'renderers.dart';
import 'reveal_video.dart';
import 'watermark.dart';

/// Turns captures into share-ready files. Every file is rendered from pixels
/// (no EXIF, location or camera data). Raw transparent cutouts are never
/// exported: only finished composites.
class ExportService {
  ExportService(this._ref);

  final Ref _ref;

  MediaStore get _store => _ref.read(mediaStoreProvider);
  bool get _watermark => !_ref.read(entitlementsProvider).isPro;

  static Future<Directory> shareDir() async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/share');
    await dir.create(recursive: true);
    return dir;
  }

  /// Deletes previously shared temp files (called at startup).
  static Future<void> clearShareDir() async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/share');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  ShareTexts texts(BuildContext context) => ShareTexts(
    watermark: context.l10n.madeWithSnipfit,
    whichOne: context.l10n.whichOne,
    aiLabel: context.l10n.aiGeneratedLabel,
  );

  Future<ui.Image> _decodeFile(File f, {int maxSide = 2160}) async =>
      (await ImageUtils.decode(await f.readAsBytes(), maxSide: maxSide)).image;

  /// Coarse map of where the fabric and the head are, to keep the
  /// watermark off both.
  Future<({Uint8List data, int w, int h})> _avoidGrid(CaptureRecord c, ui.Image cutout) async {
    const gw = 64;
    final gh = (gw * c.height / c.width).round();
    final s = gw / c.width;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(s);
    final a = c.placement;
    canvas.transform(
      Float64List.fromList([a[0], a[1], 0, 0, a[2], a[3], 0, 0, 0, 0, 1, 0, a[4], a[5], 0, 1]),
    );
    final bounds = Rect.fromLTWH(0, 0, cutout.width.toDouble(), cutout.height.toDouble());
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = Colors.white);
    canvas.drawImage(cutout, Offset.zero, Paint()..blendMode = BlendMode.dstOut);
    canvas.restore();
    // The upper part of the photo holds the face and head.
    canvas.drawRect(Rect.fromLTWH(cutout.width * 0.15, 0, cutout.width * 0.7, cutout.height * 0.5), Paint()..color = Colors.white);
    final image = await rec.endRecording().toImage(gw, gh);
    final rgba = await ImageUtils.toRgba(image);
    image.dispose();
    final data = Uint8List(gw * gh);
    for (var i = 0; i < data.length; i++) {
      data[i] = rgba[i * 4 + 3];
    }
    return (data: data, w: gw, h: gh);
  }

  Future<CaptureArt> _art(CaptureRecord c, {ui.Image? cutout}) async {
    final composite = await _decodeFile(_store.compositeFile(c.id));
    final cut = cutout ?? await _decodeFile(_store.cutoutFile(c.windowId), maxSide: 4096);
    final grid = await _avoidGrid(c, cut);
    if (cutout == null) cut.dispose();
    return CaptureArt(composite: composite, fabricArgb: c.fabricArgb, windowAlpha: grid);
  }

  Future<File> _writeJpeg(ui.Image image, String name, {bool ai = false}) async {
    var bytes = await toJpeg(image);
    if (ai) bytes = Provenance.embedInJpeg(bytes);
    final f = File('${(await shareDir()).path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  Future<File> exportSingle(CaptureRecord c, ShareTexts texts) async {
    final art = await _art(c);
    final image = await renderSingle(art, watermark: _watermark, texts: texts);
    art.composite.dispose();
    final f = await _writeJpeg(image, 'snipfit_${c.id.substring(0, 8)}.jpg');
    image.dispose();
    return f;
  }

  Future<File> exportCollage(List<CaptureRecord> captures, ShareTexts texts, {bool square = false}) async {
    final arts = <CaptureArt>[for (final c in captures.take(4)) await _art(c)];
    final image = await renderCollage(arts, watermark: _watermark, texts: texts, square: square);
    for (final a in arts) {
      a.composite.dispose();
    }
    final f = await _writeJpeg(image, 'snipfit_compare_${square ? 'square' : 'story'}.jpg');
    image.dispose();
    return f;
  }

  Future<RevealInputs> revealInputs(CaptureRecord c, ShareTexts texts) async {
    final photo = await _decodeFile(_store.photoFile(c.windowId), maxSide: 4096);
    final cutout = await _decodeFile(_store.cutoutFile(c.windowId), maxSide: 4096);
    final scene = await _decodeFile(_store.sceneFile(c.id));
    // Window contour at low resolution, scaled back to cutout pixels.
    const cw = 256;
    final ch = (cw * cutout.height / cutout.width).round();
    final small = await ImageUtils.resize(cutout, cw, ch);
    final rgba = await ImageUtils.toRgba(small);
    small.dispose();
    final grid = Uint8List(cw * ch);
    for (var i = 0; i < grid.length; i++) {
      grid[i] = rgba[i * 4 + 3] < 128 ? 1 : 0;
    }
    final k = cutout.width / cw;
    final contour = [for (final p in traceOuterContour(grid, cw, ch)) p * k];
    final avoid = await _avoidGrid(c, cutout);
    final corner = chooseCorner(
      avoid: avoid.data,
      gridW: avoid.w,
      gridH: avoid.h,
      boxW: watermarkBoxFraction.w,
      boxH: watermarkBoxFraction.h,
      blocked: const {Corner.bottomLeft},
    );
    return RevealInputs(
      photo: photo,
      cutout: cutout,
      scene: scene,
      affine: c.placement,
      compositeSize: Size(c.width.toDouble(), c.height.toDouble()),
      fabricArgb: c.fabricArgb,
      contour: contour,
      watermark: _watermark,
      texts: texts,
      watermarkCorner: corner,
    );
  }

  /// Renders the reveal video. Returns null if this device can't encode.
  Future<File?> exportReveal(CaptureRecord c, ShareTexts texts, {void Function(double)? onProgress}) async {
    final inputs = await revealInputs(c, texts);
    try {
      final path = '${(await shareDir()).path}/snipfit_reveal_${c.id.substring(0, 8)}.mp4';
      final ok = await RevealVideo.encode(inputs, path, onProgress: onProgress);
      return ok ? File(path) : null;
    } finally {
      inputs.photo.dispose();
      inputs.cutout.dispose();
      inputs.scene.dispose();
    }
  }

  /// Saves the finished single result to Photos. Asks for add-only photo
  /// access (iOS) only now, when the user taps Save.
  Future<void> saveToPhotos(BuildContext context, CaptureRecord c) async {
    final t = texts(context);
    final l10n = context.l10n;
    try {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        if (context.mounted) showSnack(context, l10n.photosAccessDenied);
        return;
      }
      final file = await exportSingle(c, t);
      await Gal.putImage(file.path);
      HapticFeedback.lightImpact();
      if (context.mounted) showSnack(context, l10n.savedToPhotos);
    } on GalException {
      if (context.mounted) showSnack(context, l10n.genericError);
    }
  }

  /// Saves an AI image with its visible label and provenance metadata.
  Future<void> saveAiToPhotos(BuildContext context, File aiImage) async {
    final l10n = context.l10n;
    final label = l10n.aiGeneratedLabel;
    try {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        if (context.mounted) showSnack(context, l10n.photosAccessDenied);
        return;
      }
      final file = await exportAi(aiImage, label);
      await Gal.putImage(file.path);
      if (context.mounted) showSnack(context, l10n.savedToPhotos);
    } on GalException {
      if (context.mounted) showSnack(context, l10n.genericError);
    }
  }

  Future<File> exportAi(File aiImage, String label) async {
    final src = await _decodeFile(aiImage);
    final labeled = await renderAiLabeled(src, label);
    src.dispose();
    final f = await _writeJpeg(labeled, 'snipfit_ai_${DateTime.now().millisecondsSinceEpoch}.jpg', ai: true);
    labeled.dispose();
    return f;
  }
}

final exportServiceProvider = Provider<ExportService>(ExportService.new);
