import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/analytics/analytics.dart';
import '../../core/analytics/analytics_events.dart';
import '../../core/flags/remote_flags.dart';
import '../../core/platform/native_channels.dart';
import '../../core/storage/media_store.dart';
import '../../design/tokens.dart';
import '../../design/widgets/common.dart';
import '../../l10n/l10n.dart';
import '../../config/app_config.dart';
import '../invite/invite_links.dart';
import '../modes/app_mode.dart';
import 'export_service.dart';
import 'reveal_video.dart';

enum ShareFormat { reveal, collage, single }

enum ShareTarget {
  instagram('instagram', Icons.camera_alt_outlined),
  tiktok('tiktok', Icons.music_note_outlined),
  snapchat('snapchat', Icons.chat_bubble_outline),
  whatsapp('whatsapp', Icons.forum_outlined),
  more('more', Icons.ios_share);

  const ShareTarget(this.id, this.icon);

  final String id;
  final IconData icon;
}

/// One share sheet: pick a format (reveal video by default), then one big
/// button per app. Any result shares in two taps from Compare.
abstract final class ShareSheet {
  static Future<void> show(
    BuildContext context, {
    required String windowId,
    required List<CaptureRecord> captures,
    required CaptureRecord focus,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ShareSheetBody(windowId: windowId, captures: captures, focus: focus),
  );
}

class _ShareSheetBody extends ConsumerStatefulWidget {
  const _ShareSheetBody({required this.windowId, required this.captures, required this.focus});

  final String windowId;
  final List<CaptureRecord> captures;
  final CaptureRecord focus;

  @override
  ConsumerState<_ShareSheetBody> createState() => _ShareSheetBodyState();
}

class _ShareSheetBodyState extends ConsumerState<_ShareSheetBody> {
  late ShareFormat _format;
  bool _square = false;
  ui.Image? _preview;
  bool _working = false;
  double? _progress;
  final _files = <String, File>{};

  @override
  void initState() {
    super.initState();
    final videoOn = ref.read(remoteFlagsProvider).revealVideoEnabled;
    _format = videoOn ? ShareFormat.reveal : ShareFormat.single;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(analyticsProvider).track(AnalyticsEvents.shareOpened, {AnalyticsProps.format: _format.name});
      _renderPreview();
    });
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  String get _cacheKey => '${_format.name}-$_square';

  Future<void> _renderPreview() async {
    final export = ref.read(exportServiceProvider);
    final texts = export.texts(context);
    ui.Image? image;
    try {
      switch (_format) {
        case ShareFormat.reveal:
          final inputs = await export.revealInputs(widget.focus, texts);
          image = await RevealVideo.poster(inputs);
          inputs.photo.dispose();
          inputs.cutout.dispose();
          inputs.scene.dispose();
        case ShareFormat.collage:
          final f = await export.exportCollage(widget.captures, texts, square: _square);
          _files[_cacheKey] = f;
          image = (await ui.instantiateImageCodec(await f.readAsBytes(), targetWidth: 540).then((c) => c.getNextFrame())).image;
        case ShareFormat.single:
          final f = await export.exportSingle(widget.focus, texts);
          _files[_cacheKey] = f;
          image = (await ui.instantiateImageCodec(await f.readAsBytes(), targetWidth: 540).then((c) => c.getNextFrame())).image;
      }
    } on Object catch (e) {
      debugPrint('share preview failed: $e');
    }
    if (!mounted) {
      image?.dispose();
      return;
    }
    setState(() {
      _preview?.dispose();
      _preview = image;
    });
  }

  Future<({File file, String mime})?> _ensureFile() async {
    final export = ref.read(exportServiceProvider);
    final texts = export.texts(context);
    final cached = _files[_cacheKey];
    if (cached != null && await cached.exists()) {
      return (file: cached, mime: cached.path.endsWith('.mp4') ? 'video/mp4' : 'image/jpeg');
    }
    switch (_format) {
      case ShareFormat.reveal:
        setState(() => _progress = 0);
        final video = await export.exportReveal(widget.focus, texts, onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        });
        if (mounted) setState(() => _progress = null);
        if (video != null) {
          _files[_cacheKey] = video;
          return (file: video, mime: 'video/mp4');
        }
        // No encoder on this device: share the single result instead.
        if (mounted) showSnack(context, context.l10n.videoUnavailable);
        final single = await export.exportSingle(widget.focus, texts);
        return (file: single, mime: 'image/jpeg');
      case ShareFormat.collage:
        final f = await export.exportCollage(widget.captures, texts, square: _square);
        _files[_cacheKey] = f;
        return (file: f, mime: 'image/jpeg');
      case ShareFormat.single:
        final f = await export.exportSingle(widget.focus, texts);
        _files[_cacheKey] = f;
        return (file: f, mime: 'image/jpeg');
    }
  }

  Future<void> _share(ShareTarget target) async {
    if (_working) return;
    setState(() => _working = true);
    final l10n = context.l10n;
    final config = ref.read(appConfigProvider);
    final mode = ref.read(modeProvider);
    final link = ref.read(inviteLinksProvider).link(mode);
    final caption = '${l10n.shareCaption} $link';
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    try {
      final out = await _ensureFile();
      if (out == null || !mounted) return;
      // Caption + invite link go to the clipboard with a one-line notice.
      await Clipboard.setData(ClipboardData(text: caption));
      if (mounted) showSnack(context, l10n.captionCopied);

      var shared = false;
      if (target != ShareTarget.more && ref.read(remoteFlagsProvider).shareKitsEnabled) {
        shared = await NativeChannels.shareTo(
          target: target.id,
          path: out.file.path,
          mimeType: out.mime,
          caption: caption,
          appIds: {
            'facebook': config.facebookAppId,
            'tiktok': config.tiktokClientKey,
            'snapchat': config.snapClientId,
          },
        );
      }
      if (!shared) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(out.file.path, mimeType: out.mime)],
            text: caption,
            sharePositionOrigin: origin,
          ),
        );
      }
      await ref.read(analyticsProvider).track(AnalyticsEvents.shareCompleted, {
        AnalyticsProps.target: shared ? target.id : 'system',
        AnalyticsProps.format: _format.name,
      });
    } on Object catch (e) {
      debugPrint('share failed: $e');
      if (mounted) showSnack(context, l10n.genericError);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final window = ref.watch(windowProvider(widget.windowId)).value;
    final canCollage = widget.captures.length >= 2;
    final videoOn = ref.watch(remoteFlagsProvider.select((f) => f.revealVideoEnabled));
    String targetLabel(ShareTarget t) => switch (t) {
      ShareTarget.instagram => l10n.targetInstagram,
      ShareTarget.tiktok => l10n.targetTiktok,
      ShareTarget.snapchat => l10n.targetSnapchat,
      ShareTarget.whatsapp => l10n.targetWhatsapp,
      ShareTarget.more => l10n.targetMore,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s2, 0, Space.s2, Space.s2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.share, style: theme.textTheme.titleLarge),
          const SizedBox(height: Space.s2),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ShareFormat>(
              showSelectedIcon: false,
              segments: [
                if (videoOn) ButtonSegment(value: ShareFormat.reveal, label: Text(l10n.formatReveal)),
                ButtonSegment(value: ShareFormat.collage, label: Text(l10n.formatCompare), enabled: canCollage),
                ButtonSegment(value: ShareFormat.single, label: Text(l10n.formatSingle)),
              ],
              selected: {_format},
              onSelectionChanged: (s) {
                setState(() => _format = s.first);
                ref.read(analyticsProvider).track(AnalyticsEvents.shareOpened, {AnalyticsProps.format: _format.name});
                _renderPreview();
              },
            ),
          ),
          if (_format == ShareFormat.collage)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.squareFormat),
              value: _square,
              onChanged: (v) {
                setState(() => _square = v);
                _renderPreview();
              },
            ),
          const SizedBox(height: Space.s2),
          SizedBox(
            height: 300,
            child: Center(
              child: _preview == null
                  ? const CircularProgressIndicator()
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.card),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          RawImage(image: _preview, fit: BoxFit.contain),
                          if (_format == ShareFormat.reveal)
                            const Icon(Icons.play_circle_fill, size: 56, color: Colors.white70),
                        ],
                      ),
                    ),
            ),
          ),
          if (_progress != null) ...[
            const SizedBox(height: Space.s1),
            LinearProgressIndicator(value: _progress, semanticsLabel: l10n.renderingVideo),
          ],
          if (window?.someoneElse ?? false) ...[
            const SizedBox(height: Space.s1),
            Text(l10n.someoneElseShareReminder, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          ],
          const SizedBox(height: Space.s2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final t in ShareTarget.values)
                _TargetButton(icon: t.icon, label: targetLabel(t), onTap: _working ? null : () => _share(t)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TargetButton extends StatelessWidget {
  const _TargetButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.card),
        child: SizedBox(
          width: 64,
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh, shape: BoxShape.circle),
                child: Icon(icon, color: onTap == null ? theme.disabledColor : theme.colorScheme.onSurface),
              ),
              const SizedBox(height: Space.xs),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
