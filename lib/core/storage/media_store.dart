import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../features/cutout/mask/hijab_template.dart';
import '../../features/cutout/mask/mask_builder.dart';
import '../../features/modes/app_mode.dart';
import '../platform/native_channels.dart';

/// A saved window: the person's photo plus the finished cutout (the photo
/// with the garment area made transparent). No landmarks or segmentation
/// maps are stored; they are recomputed in memory if the window is edited.
@immutable
class WindowRecord {
  const WindowRecord({
    required this.id,
    required this.mode,
    required this.createdAt,
    required this.strategy,
    required this.width,
    required this.height,
    required this.quality,
    this.hijabStyle,
    this.someoneElse = false,
  });

  final String id;
  final AppMode mode;
  final DateTime createdAt;
  final WindowStrategy strategy;
  final HijabStyle? hijabStyle;
  final int width;
  final int height;
  final double quality;

  /// Photo shows someone other than the user ("Try on someone else"), who
  /// gave permission. Shares remind the user to respect that.
  final bool someoneElse;

  Map<String, Object?> toJson() => {
    'id': id,
    'mode': mode.name,
    'createdAt': createdAt.toIso8601String(),
    'strategy': strategy.name,
    'hijabStyle': hijabStyle?.name,
    'width': width,
    'height': height,
    'quality': quality,
    'someoneElse': someoneElse,
  };

  static WindowRecord fromJson(Map<String, Object?> j) => WindowRecord(
    id: j['id']! as String,
    mode: AppMode.tryParse(j['mode'] as String?) ?? AppMode.women,
    createdAt: DateTime.parse(j['createdAt']! as String),
    strategy: WindowStrategy.values.firstWhere(
      (s) => s.name == j['strategy'],
      orElse: () => WindowStrategy.garment,
    ),
    hijabStyle: HijabStyle.values.where((s) => s.name == j['hijabStyle']).firstOrNull,
    width: (j['width']! as num).toInt(),
    height: (j['height']! as num).toInt(),
    quality: (j['quality'] as num?)?.toDouble() ?? 0,
    someoneElse: j['someoneElse'] as bool? ?? false,
  );
}

/// One live-window capture: the finished composite (what was on screen), the
/// camera scene behind it (for the reveal video) and the sampled fabric color.
@immutable
class CaptureRecord {
  const CaptureRecord({
    required this.id,
    required this.windowId,
    required this.createdAt,
    required this.fabricArgb,
    required this.width,
    required this.height,
    required this.placement,
    this.favorite = false,
  });

  final String id;
  final String windowId;
  final DateTime createdAt;
  final int fabricArgb;
  final int width;
  final int height;

  /// Affine placement of the cutout in composite pixels:
  /// [a, b, c, d, tx, ty] mapping cutout coordinates to composite coordinates.
  final List<double> placement;
  final bool favorite;

  String get hex {
    final rgb = fabricArgb & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  CaptureRecord copyWith({bool? favorite}) => CaptureRecord(
    id: id,
    windowId: windowId,
    createdAt: createdAt,
    fabricArgb: fabricArgb,
    width: width,
    height: height,
    placement: placement,
    favorite: favorite ?? this.favorite,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'windowId': windowId,
    'createdAt': createdAt.toIso8601String(),
    'fabricArgb': fabricArgb,
    'width': width,
    'height': height,
    'placement': placement,
    'favorite': favorite,
  };

  static CaptureRecord fromJson(Map<String, Object?> j) => CaptureRecord(
    id: j['id']! as String,
    windowId: j['windowId']! as String,
    createdAt: DateTime.parse(j['createdAt']! as String),
    fabricArgb: (j['fabricArgb']! as num).toInt(),
    width: (j['width']! as num).toInt(),
    height: (j['height']! as num).toInt(),
    placement: [for (final v in (j['placement']! as List)) (v as num).toDouble()],
    favorite: j['favorite'] as bool? ?? false,
  );
}

/// Private on-device storage for windows and captures. Files live in the
/// app's support directory, excluded from device backups.
class MediaStore {
  MediaStore(this.root);

  final Directory root;

  static Future<MediaStore> open() async {
    final base = await getApplicationSupportDirectory();
    final root = Directory('${base.path}/media');
    await root.create(recursive: true);
    await NativeChannels.excludeFromBackup(root.path);
    return MediaStore(root);
  }

  Directory get _windows => Directory('${root.path}/windows');
  Directory get _captures => Directory('${root.path}/captures');

  Directory windowDir(String id) => Directory('${_windows.path}/$id');
  Directory captureDir(String id) => Directory('${_captures.path}/$id');

  File photoFile(String windowId) => File('${windowDir(windowId).path}/photo.jpg');
  File cutoutFile(String windowId) => File('${windowDir(windowId).path}/cutout.png');
  File thumbFile(String windowId) => File('${windowDir(windowId).path}/thumb.jpg');
  File compositeFile(String captureId) => File('${captureDir(captureId).path}/composite.jpg');
  File sceneFile(String captureId) => File('${captureDir(captureId).path}/scene.jpg');

  static String newId() => const Uuid().v4();

  Future<List<WindowRecord>> listWindows() async {
    if (!await _windows.exists()) return const [];
    final out = <WindowRecord>[];
    await for (final dir in _windows.list()) {
      if (dir is! Directory) continue;
      final meta = File('${dir.path}/meta.json');
      if (!await meta.exists()) continue;
      try {
        out.add(WindowRecord.fromJson((jsonDecode(await meta.readAsString()) as Map).cast()));
      } on Object {
        // Skip unreadable entries rather than failing the whole list.
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<WindowRecord?> getWindow(String id) async {
    final meta = File('${windowDir(id).path}/meta.json');
    if (!await meta.exists()) return null;
    return WindowRecord.fromJson((jsonDecode(await meta.readAsString()) as Map).cast());
  }

  Future<void> saveWindow(
    WindowRecord record, {
    required Uint8List photoJpeg,
    required Uint8List cutoutPng,
    required Uint8List thumbJpeg,
  }) async {
    final dir = windowDir(record.id);
    await dir.create(recursive: true);
    await photoFile(record.id).writeAsBytes(photoJpeg, flush: true);
    await cutoutFile(record.id).writeAsBytes(cutoutPng, flush: true);
    await thumbFile(record.id).writeAsBytes(thumbJpeg, flush: true);
    await File('${dir.path}/meta.json').writeAsString(jsonEncode(record.toJson()), flush: true);
  }

  Future<void> deleteWindow(String id) async {
    for (final c in await listCaptures(id)) {
      await deleteCapture(c.id);
    }
    final dir = windowDir(id);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<List<CaptureRecord>> listCaptures(String windowId) async {
    if (!await _captures.exists()) return const [];
    final out = <CaptureRecord>[];
    await for (final dir in _captures.list()) {
      if (dir is! Directory) continue;
      final meta = File('${dir.path}/meta.json');
      if (!await meta.exists()) continue;
      try {
        final rec = CaptureRecord.fromJson((jsonDecode(await meta.readAsString()) as Map).cast());
        if (rec.windowId == windowId) out.add(rec);
      } on Object {
        // Skip unreadable entries.
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<void> saveCapture(
    CaptureRecord record, {
    required Uint8List compositeJpeg,
    required Uint8List sceneJpeg,
  }) async {
    final dir = captureDir(record.id);
    await dir.create(recursive: true);
    await compositeFile(record.id).writeAsBytes(compositeJpeg, flush: true);
    await sceneFile(record.id).writeAsBytes(sceneJpeg, flush: true);
    await writeCaptureMeta(record);
  }

  Future<void> writeCaptureMeta(CaptureRecord record) =>
      File('${captureDir(record.id).path}/meta.json').writeAsString(jsonEncode(record.toJson()), flush: true);

  Future<void> deleteCapture(String id) async {
    final dir = captureDir(id);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Deletes every window, capture and AI result on this device.
  Future<void> deleteAll() async {
    if (await root.exists()) await root.delete(recursive: true);
    await root.create(recursive: true);
  }

  Directory get aiDir => Directory('${root.path}/ai');
}

final mediaStoreProvider = Provider<MediaStore>(
  (ref) => throw UnimplementedError('MediaStore is provided in bootstrap'),
);

/// Bumped whenever windows or captures change so lists refresh.
class MediaRevision extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final mediaRevisionProvider = NotifierProvider<MediaRevision, int>(MediaRevision.new);

final windowsProvider = FutureProvider<List<WindowRecord>>((ref) {
  ref.watch(mediaRevisionProvider);
  return ref.watch(mediaStoreProvider).listWindows();
});

final windowProvider = FutureProvider.family<WindowRecord?, String>((ref, id) {
  ref.watch(mediaRevisionProvider);
  return ref.watch(mediaStoreProvider).getWindow(id);
});

final capturesProvider = FutureProvider.family<List<CaptureRecord>, String>((ref, windowId) {
  ref.watch(mediaRevisionProvider);
  return ref.watch(mediaStoreProvider).listCaptures(windowId);
});
