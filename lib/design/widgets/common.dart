import 'package:flutter/material.dart';

import '../tokens.dart';

/// Fabric swatch with its hex code.
class SwatchChip extends StatelessWidget {
  const SwatchChip({required this.color, required this.hex, this.compact = false, super.key});

  final Color color;
  final String hex;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = compact ? 16.0 : 22.0;
    return Semantics(
      label: hex,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(Radii.chip),
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : Space.s1,
            vertical: compact ? 4 : 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black12),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                hex,
                style: (compact ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)
                    ?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: theme.colorScheme.onSurface,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Unticked-by-default consent checkbox with the whole row tappable.
class ConsentCheckbox extends StatelessWidget {
  const ConsentCheckbox({
    required this.value,
    required this.onChanged,
    required this.label,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.chip),
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.minTap),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Text(label, style: theme.textTheme.bodyLarge),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small pill badge, used for Pro and credit balances.
class PillBadge extends StatelessWidget {
  const PillBadge({required this.label, this.icon, this.emphasized = false, this.onTap, super.key});

  final String label;
  final IconData? icon;
  final bool emphasized;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = emphasized ? theme.colorScheme.surface : theme.colorScheme.onSurface;
    final bg = emphasized ? theme.colorScheme.onSurface : theme.colorScheme.surfaceContainerHigh;
    return Semantics(
      button: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.button),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.button),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36, minWidth: Sizes.minTap),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
                  Text(label, style: theme.textTheme.labelMedium?.copyWith(color: fg)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Section header used in lists and Settings.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(Space.s2, Space.s3, Space.s2, Space.s1),
        child: Text(title.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 0.8)),
      ),
    );
  }
}

/// Shows a short, neutral message.
void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
