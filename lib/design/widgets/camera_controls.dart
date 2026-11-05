import 'package:flutter/material.dart';

import '../tokens.dart';

/// Round control over the camera: translucent black with a white icon, so it
/// never casts a color onto how the fabric is judged.
class CameraControlButton extends StatelessWidget {
  const CameraControlButton({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.selected = false,
    this.label,
    super.key,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool selected;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: selected ? SnipColors.cameraOnScrim : SnipColors.cameraScrim,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: Sizes.cameraControl,
            child: Icon(
              icon,
              size: 26,
              color: selected ? SnipColors.ink : SnipColors.cameraOnScrim,
            ),
          ),
        ),
      ),
    );
    if (label == null) return button;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        const SizedBox(height: Space.xs),
        Text(
          label!,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: SnipColors.cameraOnScrim,
            shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
          ),
        ),
      ],
    );
  }
}

/// The capture button: a white ring with a solid center.
class ShutterButton extends StatefulWidget {
  const ShutterButton({
    required this.onPressed,
    required this.semanticLabel,
    this.busy = false,
    super.key,
  });

  final VoidCallback? onPressed;
  final String semanticLabel;
  final bool busy;

  @override
  State<ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<ShutterButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled
            ? (_) {
                setState(() => _down = false);
                widget.onPressed!();
              }
            : null,
        child: SizedBox.square(
          dimension: Sizes.shutter,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: SnipColors.cameraOnScrim, width: 5),
              color: SnipColors.cameraScrim,
            ),
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: AnimatedScale(
                scale: _down ? 0.86 : 1,
                duration: Motion.of(context, Motion.fast),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: enabled
                        ? SnipColors.cameraOnScrim
                        : SnipColors.cameraControl,
                  ),
                  child: widget.busy
                      ? const Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: SnipColors.ink,
                          ),
                        )
                      : const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single short line of instruction over the camera.
class CameraHint extends StatelessWidget {
  const CameraHint(this.text, {this.onClose, this.closeLabel, super.key});

  final String text;
  final VoidCallback? onClose;
  final String? closeLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: SnipColors.cameraScrim,
          borderRadius: BorderRadius.circular(Radii.chip * 2),
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: Space.s2,
            end: onClose == null ? Space.s2 : Space.xs,
            top: Space.xs,
            bottom: Space.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.s1),
                  child: Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: SnipColors.cameraOnScrim,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              if (onClose != null)
                IconButton(
                  onPressed: onClose,
                  tooltip: closeLabel,
                  icon: const Icon(Icons.close, color: SnipColors.cameraOnScrim),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
