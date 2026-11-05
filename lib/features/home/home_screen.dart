import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/media_store.dart';
import '../../design/illustrations/figure_art.dart';
import '../../design/tokens.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/common.dart';
import '../../l10n/l10n.dart';
import '../cutout/cutout_controller.dart';
import '../modes/app_mode.dart';
import '../paywall/entitlements.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final mode = ref.watch(modeProvider);
    final modes = ref.watch(availableModesProvider);
    final windows = ref.watch(windowsProvider);
    final ent = ref.watch(entitlementsProvider);

    String modeName(AppMode m) => switch (m) {
      AppMode.women => l10n.modeWomen,
      AppMode.hijab => l10n.modeHijab,
      AppMode.men => l10n.modeMen,
    };

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Text('Snipfit', style: theme.textTheme.titleLarge),
        actions: [
          PillBadge(
            label: ent.isPro ? l10n.proBadge : l10n.creditsBadge(ent.aiTryOnsAvailable),
            icon: ent.isPro ? Icons.workspace_premium_outlined : Icons.auto_awesome_outlined,
            emphasized: ent.isPro,
            onTap: () => context.push('/paywall?trigger=home_badge'),
          ),
          IconButton(
            tooltip: l10n.settings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
          const SizedBox(width: Space.xs),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Space.s2, Space.s1, Space.s2, 0),
              sliver: SliverToBoxAdapter(
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<AppMode>(
                    showSelectedIcon: false,
                    segments: [for (final m in modes) ButtonSegment(value: m, label: Text(modeName(m)))],
                    selected: {mode},
                    onSelectionChanged: (s) => ref.read(modeProvider.notifier).select(s.first),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(Space.s2),
              sliver: SliverToBoxAdapter(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.s2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l10n.aiCardTitle, style: theme.textTheme.titleMedium),
                              const SizedBox(height: 2),
                              Text(l10n.aiCardBody, style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                        const SizedBox(width: Space.s1),
                        FilledButton.tonal(onPressed: () => context.push('/ai'), child: Text(l10n.tryIt)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s2),
              sliver: SliverToBoxAdapter(child: Text(l10n.recentWindows, style: theme.textTheme.titleMedium)),
            ),
            ...windows.when(
              loading: () => [const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(Space.s4), child: Center(child: CircularProgressIndicator())))],
              error: (_, _) => [SliverToBoxAdapter(child: Center(child: Text(l10n.genericError)))],
              data: (list) => list.isEmpty
                  ? [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const EmptyWindowsArt(),
                            const SizedBox(height: Space.s2),
                            Text(l10n.emptyWindowsTitle, style: theme.textTheme.titleMedium),
                          ],
                        ),
                      ),
                    ]
                  : [
                      SliverPadding(
                        padding: const EdgeInsets.all(Space.s2),
                        sliver: SliverGrid.builder(
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 180,
                            mainAxisSpacing: Space.s1,
                            crossAxisSpacing: Space.s1,
                            childAspectRatio: 3 / 4,
                          ),
                          itemCount: list.length,
                          itemBuilder: (context, i) => _WindowTile(record: list[i]),
                        ),
                      ),
                    ],
            ),
          ],
        ),
      ),
      // Primary action in the thumb zone.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.s2, Space.s1, Space.s2, Space.s2),
          child: PrimaryButton(
            label: (windows.value?.isEmpty ?? true) ? l10n.makeFirstWindow : l10n.newWindow,
            icon: Icons.content_cut,
            onPressed: () => context.push('/capture'),
          ),
        ),
      ),
    );
  }
}

class _WindowTile extends ConsumerWidget {
  const _WindowTile({required this.record});

  final WindowRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final store = ref.watch(mediaStoreProvider);
    final date = MaterialLocalizations.of(context).formatShortDate(record.createdAt);
    return Semantics(
      button: true,
      label: l10n.windowTileLabel(date),
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.card),
        child: Material(
          child: InkWell(
            onTap: () => context.push('/live/${record.id}'),
            onLongPress: () => _options(context, ref),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(store.thumbFile(record.id), fit: BoxFit.cover),
                PositionedDirectional(
                  end: 4,
                  top: 4,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: l10n.moreOptions,
                      icon: const Icon(Icons.more_horiz, color: Colors.white),
                      onPressed: () => _options(context, ref),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _options(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.grid_view_rounded), title: Text(l10n.compare), onTap: () => Navigator.pop(context, 'compare')),
            ListTile(leading: const Icon(Icons.edit_outlined), title: Text(l10n.editWindow), onTap: () => Navigator.pop(context, 'edit')),
            ListTile(leading: const Icon(Icons.delete_outline), title: Text(l10n.delete), onTap: () => Navigator.pop(context, 'delete')),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'compare':
        await context.push('/compare/${record.id}');
      case 'edit':
        final bytes = await ref.read(mediaStoreProvider).photoFile(record.id).readAsBytes();
        await ref.read(modeProvider.notifier).select(record.mode);
        // Start analysis and show Refine's progress state right away.
        unawaited(ref.read(cutoutControllerProvider.notifier).start(
          bytes,
          source: CaptureSource.upload,
          someoneElse: record.someoneElse,
          editingWindowId: record.id,
          strategyOverride: record.strategy,
          styleOverride: record.hijabStyle,
        ));
        if (context.mounted) await context.push('/refine');
      case 'delete':
        await ref.read(mediaStoreProvider).deleteWindow(record.id);
        ref.read(mediaRevisionProvider.notifier).bump();
    }
  }
}
