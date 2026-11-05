import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_review/in_app_review.dart';

import '../../core/backend/backend.dart';
import '../../core/flags/remote_flags.dart';
import '../../core/notifications/notifications.dart';
import '../../core/storage/local_store.dart';
import '../../core/storage/media_store.dart';
import '../../design/tokens.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/common.dart';
import '../../l10n/l10n.dart';
import '../live_window/compositor.dart';
import '../share/export_service.dart';
import '../share/share_sheet.dart';

/// The last four captures side by side, with a favorite and swatches.
class CompareScreen extends ConsumerStatefulWidget {
  const CompareScreen({required this.windowId, this.firstRun = false, super.key});

  final String windowId;
  final bool firstRun;

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAskNotifications());
  }

  /// Notification permission is asked only now (after a first saved
  /// comparison) and only if AI try-on, the one thing we notify about, exists.
  Future<void> _maybeAskNotifications() async {
    final store = ref.read(localStoreProvider);
    if (store.getBool(Keys.notificationsAsked)) return;
    if (!ref.read(backendStatusProvider).firebaseReady) return;
    if (!ref.read(remoteFlagsProvider).aiTryOnEnabled) return;
    await store.setBool(Keys.notificationsAsked, true);
    if (!mounted) return;
    final l10n = context.l10n;
    final yes = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.s3, 0, Space.s3, Space.s3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.notifyTitle, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: Space.s1),
              Text(l10n.notifyBody, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: Space.s3),
              PrimaryButton(label: l10n.notifyAllow, onPressed: () => Navigator.pop(context, true)),
              const SizedBox(height: Space.s1),
              SecondaryButton(label: l10n.notNow, onPressed: () => Navigator.pop(context, false)),
            ],
          ),
        ),
      ),
    );
    if (yes ?? false) await ref.read(notificationsProvider).requestPermission();
  }

  Future<void> _toggleFavorite(CaptureRecord c, List<CaptureRecord> all) async {
    final store = ref.read(mediaStoreProvider);
    final makeFavorite = !c.favorite;
    for (final other in all) {
      if (other.favorite && other.id != c.id) await store.writeCaptureMeta(other.copyWith(favorite: false));
    }
    await store.writeCaptureMeta(c.copyWith(favorite: makeFavorite));
    ref.read(mediaRevisionProvider.notifier).bump();
    if (makeFavorite && all.length >= 2) unawaited(_maybeRequestReview());
  }

  /// Native review prompt only, only after a positive moment, at most once
  /// every 120 days. Never tied to a reward.
  Future<void> _maybeRequestReview() async {
    final store = ref.read(localStoreProvider);
    final last = store.getInt(Keys.reviewAskedAt);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (last != null && now - last < const Duration(days: 120).inMilliseconds) return;
    final review = InAppReview.instance;
    if (await review.isAvailable()) {
      await store.setInt(Keys.reviewAskedAt, now);
      await review.requestReview();
    }
  }

  void _onClose() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
    // Soft paywall: once, after the first successful compare.
    final store = ref.read(localStoreProvider);
    final flags = ref.read(remoteFlagsProvider);
    if (flags.softPaywallEnabled && !store.getBool(Keys.softPaywallShown) && store.getBool(Keys.firstCompareDone)) {
      store.setBool(Keys.softPaywallShown, true);
      final router = GoRouter.of(context);
      scheduleMicrotask(() => router.push('/paywall?trigger=soft_first_compare'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final capturesAsync = ref.watch(capturesProvider(widget.windowId));
    final all = capturesAsync.value ?? const <CaptureRecord>[];
    final shown = all.take(4).toList();
    final favorite = all.where((c) => c.favorite).firstOrNull;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onClose();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(tooltip: l10n.back, icon: const BackButtonIcon(), onPressed: _onClose),
          title: Text(l10n.compareTitle),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: shown.isEmpty
                    ? Center(child: Text(l10n.compareEmpty))
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.s2),
                        child: _Grid(
                          captures: shown,
                          onFavorite: (c) => _toggleFavorite(c, all),
                          onOpen: (c) => _openViewer(context, c),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.s2, Space.s1, Space.s2, Space.s2),
                child: Column(
                  children: [
                    PrimaryButton(
                      label: l10n.share,
                      icon: Icons.ios_share,
                      onPressed: shown.isEmpty
                          ? null
                          : () => ShareSheet.show(
                              context,
                              windowId: widget.windowId,
                              captures: shown,
                              focus: favorite ?? shown.first,
                            ),
                    ),
                    const SizedBox(height: Space.s1),
                    Row(
                      children: [
                        Expanded(
                          child: SecondaryButton(
                            label: l10n.saveToPhotos,
                            icon: Icons.download_outlined,
                            onPressed: shown.isEmpty
                                ? null
                                : () => ref.read(exportServiceProvider).saveToPhotos(context, favorite ?? shown.first),
                          ),
                        ),
                        const SizedBox(width: Space.s1),
                        Expanded(
                          child: SecondaryButton(
                            label: l10n.aiLook,
                            icon: Icons.auto_awesome_outlined,
                            onPressed: () => context.push('/ai?window=${widget.windowId}'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openViewer(BuildContext context, CaptureRecord c) => Navigator.of(context).push(
    MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => CaptureViewer(capture: c)),
  );
}

class _Grid extends ConsumerWidget {
  const _Grid({required this.captures, required this.onFavorite, required this.onOpen});

  final List<CaptureRecord> captures;
  final ValueChanged<CaptureRecord> onFavorite;
  final ValueChanged<CaptureRecord> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(mediaStoreProvider);
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = Space.s1;
        final tileW = (constraints.maxWidth - gap) / 2;
        final tileH = (constraints.maxHeight - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < captures.length; i++)
              SizedBox(
                width: tileW,
                height: tileH,
                child: _Tile(
                  capture: captures[i],
                  file: store.compositeFile(captures[i].id),
                  label: l10n.captureTileLabel(i + 1, captures[i].hex),
                  onFavorite: () => onFavorite(captures[i]),
                  onOpen: () => onOpen(captures[i]),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.capture, required this.file, required this.label, required this.onFavorite, required this.onOpen});

  final CaptureRecord capture;
  final File file;
  final String label;
  final VoidCallback onFavorite;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.card),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            button: true,
            label: label,
            child: GestureDetector(onTap: onOpen, child: Image.file(file, fit: BoxFit.cover, gaplessPlayback: true)),
          ),
          PositionedDirectional(
            top: Space.xs,
            end: Space.xs,
            child: Material(
              color: Colors.black.withValues(alpha: 0.35),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: capture.favorite ? l10n.unfavorite : l10n.favorite,
                onPressed: onFavorite,
                icon: Icon(capture.favorite ? Icons.favorite : Icons.favorite_border, color: Colors.white),
              ),
            ),
          ),
          PositionedDirectional(
            start: Space.s1,
            bottom: Space.s1,
            child: SwatchChip(color: Color(capture.fabricArgb), hex: hexOf(capture.fabricArgb), compact: true),
          ),
        ],
      ),
    );
  }
}

/// One capture, full screen, with save, share and delete.
class CaptureViewer extends ConsumerWidget {
  const CaptureViewer({required this.capture, super.key});

  final CaptureRecord capture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final store = ref.watch(mediaStoreProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: l10n.delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await store.deleteCapture(capture.id);
              ref.read(mediaRevisionProvider.notifier).bump();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: InteractiveViewer(child: Center(child: Image.file(store.compositeFile(capture.id))))),
            Padding(
              padding: const EdgeInsets.all(Space.s2),
              child: Row(
                children: [
                  SwatchChip(color: Color(capture.fabricArgb), hex: hexOf(capture.fabricArgb)),
                  const Spacer(),
                  IconButton.filledTonal(
                    tooltip: l10n.saveToPhotos,
                    onPressed: () => ref.read(exportServiceProvider).saveToPhotos(context, capture),
                    icon: const Icon(Icons.download_outlined),
                  ),
                  const SizedBox(width: Space.s1),
                  IconButton.filled(
                    tooltip: l10n.share,
                    onPressed: () => ShareSheet.show(context, windowId: capture.windowId, captures: [capture], focus: capture),
                    icon: const Icon(Icons.ios_share),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
