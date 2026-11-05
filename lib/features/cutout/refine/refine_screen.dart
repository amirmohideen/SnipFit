import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/analytics/analytics_events.dart';
import '../../../design/illustrations/snip_animation.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/buttons.dart';
import '../../../design/widgets/common.dart';
import '../../../l10n/l10n.dart';
import '../../modes/app_mode.dart';
import '../cutout_controller.dart';
import '../mask/hijab_template.dart';
import '../mask/mask_builder.dart';
import '../mask/photo_checks.dart';
import 'refine_canvas.dart';
import 'refine_model.dart';

class RefineScreen extends ConsumerStatefulWidget {
  const RefineScreen({this.guided = false, super.key});

  final bool guided;

  @override
  ConsumerState<RefineScreen> createState() => _RefineScreenState();
}

class _RefineScreenState extends ConsumerState<RefineScreen> {
  RefineModel? _model;
  CutoutSession? _modelSession;
  bool _celebrate = false;
  bool _celebrated = false;
  bool _saving = false;

  RefineModel _modelFor(CutoutSession session) {
    if (!identical(session, _modelSession)) {
      _model?.dispose();
      _model = RefineModel(session);
      _modelSession = session;
      if (!_celebrated) {
        _celebrated = true;
        _celebrate = true;
        HapticFeedback.lightImpact();
        Timer(const Duration(milliseconds: 1800), () {
          if (mounted) setState(() => _celebrate = false);
        });
      }
    }
    return _model!;
  }

  @override
  void dispose() {
    _model?.dispose();
    super.dispose();
  }

  void _retake() {
    ref.read(cutoutControllerProvider.notifier).reset();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/capture');
    }
  }

  Future<void> _done(RefineModel model) async {
    setState(() => _saving = true);
    try {
      if (model.edited) {
        await ref.read(analyticsProvider).track(AnalyticsEvents.refineUsed, {
          AnalyticsProps.tool: model.toolsUsed.join(','),
        });
      }
      final record = await ref.read(cutoutControllerProvider.notifier).save(model.current, softness: model.softness);
      HapticFeedback.mediumImpact();
      ref.read(cutoutControllerProvider.notifier).reset();
      if (!mounted) return;
      context.go('/live/${record.id}${widget.guided ? '?practice=1' : ''}');
    } on Object {
      if (mounted) showSnack(context, context.l10n.genericError);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(cutoutControllerProvider);
    return switch (state) {
      CutoutIdle() || CutoutAnalyzing() => _Analyzing(label: l10n.snipping),
      CutoutNeedsFix(:final issue, :final pending) => _NeedsFix(
        issue: issue,
        onRetake: _retake,
        onUseAnyway: pending == null ? null : () => ref.read(cutoutControllerProvider.notifier).useAnyway(),
      ),
      CutoutFailed() => _NeedsFix(issue: null, onRetake: _retake),
      CutoutReady(:final session) => _buildEditor(context, session),
    };
  }

  Widget _buildEditor(BuildContext context, CutoutSession session) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final model = _modelFor(session);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: l10n.retake, icon: const Icon(Icons.close), onPressed: _retake),
        title: Text(l10n.refineTitle),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RefineCanvas(model: model, semanticLabel: l10n.refineCanvasLabel),
                  if (_celebrate)
                    IgnorePointer(
                      child: Center(child: SnipCelebration(label: l10n.windowReady)),
                    ),
                ],
              ),
            ),
            ListenableBuilder(
              listenable: model,
              builder: (context, _) => Material(
                color: theme.colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.s2, Space.s1, Space.s2, Space.s2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (session.mode == AppMode.hijab) _HijabOptions(session: session),
                      _ToolRow(model: model),
                      Row(
                        children: [
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: Space.s1),
                            child: Text(l10n.edgeSoftness, style: theme.textTheme.labelMedium),
                          ),
                          Expanded(
                            child: Slider(
                              value: model.softness.toDouble(),
                              max: 10,
                              divisions: 10,
                              label: '${model.softness}',
                              semanticFormatterCallback: (v) => l10n.edgeSoftnessValue(v.round()),
                              onChanged: (v) => model.setSoftness(v.round()),
                            ),
                          ),
                        ],
                      ),
                      PrimaryButton(label: l10n.done, busy: _saving, onPressed: () => _done(model)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.model});

  final RefineModel model;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget tool(IconData icon, String label, VoidCallback? onTap, {bool selected = false}) => Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.chip),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: Sizes.minTap + 8),
            decoration: BoxDecoration(
              color: selected ? Theme.of(context).colorScheme.onSurface : null,
              borderRadius: BorderRadius.circular(Radii.chip),
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: onTap == null
                      ? Theme.of(context).disabledColor
                      : selected
                      ? Theme.of(context).colorScheme.surface
                      : null,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected ? Theme.of(context).colorScheme.surface : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Row(
        children: [
          tool(Icons.brush_outlined, l10n.brush, () => model.setTool(RefineTool.brush), selected: model.tool == RefineTool.brush),
          tool(Icons.auto_fix_off_outlined, l10n.eraser, () => model.setTool(RefineTool.eraser), selected: model.tool == RefineTool.eraser),
          tool(Icons.undo, l10n.undo, model.canUndo ? model.undo : null),
          tool(Icons.redo, l10n.redo, model.canRedo ? model.redo : null),
          tool(Icons.restart_alt, l10n.resetToAuto, model.edited ? model.resetToAuto : null),
        ],
      ),
    );
  }
}

class _HijabOptions extends ConsumerWidget {
  const _HijabOptions({required this.session});

  final CutoutSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(cutoutControllerProvider.notifier);
    final template = session.strategy == WindowStrategy.hijabTemplate;
    String styleName(HijabStyle s) => switch (s) {
      HijabStyle.classicWrap => l10n.styleClassicWrap,
      HijabStyle.khimar => l10n.styleKhimar,
      HijabStyle.shayla => l10n.styleShayla,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s1),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(l10n.wearingHijab)),
                ButtonSegment(value: true, label: Text(l10n.tryHijabStyle)),
              ],
              selected: {template},
              onSelectionChanged: (s) => controller.rebuild(
                strategy: s.first ? WindowStrategy.hijabTemplate : WindowStrategy.hijabWorn,
              ),
            ),
          ),
          if (template) ...[
            const SizedBox(height: Space.s1),
            Wrap(
              spacing: Space.s1,
              children: [
                for (final s in HijabStyle.values)
                  ChoiceChip(
                    label: Text(styleName(s)),
                    selected: session.style == s,
                    onSelected: (_) => controller.rebuild(strategy: WindowStrategy.hijabTemplate, style: s),
                  ),
              ],
            ),
            Text(l10n.dragHandlesHint, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _Analyzing extends StatelessWidget {
  const _Analyzing({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Semantics(
          liveRegion: true,
          label: label,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SnipSpinner(),
              const SizedBox(height: Space.s2),
              Text(label, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _NeedsFix extends StatelessWidget {
  const _NeedsFix({required this.issue, required this.onRetake, this.onUseAnyway});

  final PhotoIssue? issue;
  final VoidCallback onRetake;
  final VoidCallback? onUseAnyway;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final message = switch (issue) {
      PhotoIssue.noFace => l10n.fixNoFace,
      PhotoIssue.multipleFaces => l10n.fixMultipleFaces,
      PhotoIssue.tooDark => l10n.fixTooDark,
      PhotoIssue.tooBright => l10n.fixTooBright,
      PhotoIssue.notFrontal => l10n.fixNotFrontal,
      PhotoIssue.tooFar => l10n.fixTooFar,
      null => l10n.fixGeneric,
    };
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Icon(Icons.wb_sunny_outlined, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: Space.s2),
              Semantics(liveRegion: true, child: Text(message, style: Theme.of(context).textTheme.displaySmall)),
              const Spacer(),
              PrimaryButton(label: l10n.retake, onPressed: onRetake),
              if (onUseAnyway != null) ...[
                const SizedBox(height: Space.s1),
                SecondaryButton(label: l10n.useAnyway, onPressed: onUseAnyway),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
