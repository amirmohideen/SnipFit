import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';
import 'figure_art.dart';

/// Scissors opening and closing while a cut line is traced. Static under
/// reduce-motion.
class SnipSpinner extends StatefulWidget {
  const SnipSpinner({this.size = 72, super.key});

  final double size;

  @override
  State<SnipSpinner> createState() => _SnipSpinnerState();
}

class _SnipSpinnerState extends State<SnipSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: _SpinnerPainter(_c.value, color),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.42;
    final dash = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var a = 0.0; a < 2 * math.pi; a += 0.3) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a, 0.15, false, dash);
    }
    final angle = 2 * math.pi * t;
    final pos = c + Offset(math.cos(angle), math.sin(angle)) * r;
    final open = 0.25 + 0.35 * (0.5 + 0.5 * math.sin(t * 8 * math.pi));
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(angle + math.pi / 2 + math.pi / 4);
    ScissorsPainter.paintAt(canvas, Offset.zero, size.width * 0.34, open, color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) => old.t != t;
}

/// "Your window is ready": a short, satisfying snip moment.
class SnipCelebration extends StatelessWidget {
  const SnipCelebration({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.of(context, const Duration(milliseconds: 420)),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0, 1),
        child: Transform.scale(scale: 0.85 + 0.15 * v, child: child),
      ),
      child: Semantics(
        liveRegion: true,
        label: label,
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(Radii.card),
            boxShadow: const [BoxShadow(blurRadius: 24, color: Color(0x33000000))],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: Space.s2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(
                  size: const Size.square(36),
                  painter: _StaticScissors(theme.colorScheme.onSurface),
                ),
                const SizedBox(width: Space.s1),
                Text(label, style: theme.textTheme.titleMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StaticScissors extends CustomPainter {
  _StaticScissors(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) =>
      ScissorsPainter.paintAt(canvas, size.center(Offset.zero), size.width * 0.9, 0.5, color);

  @override
  bool shouldRepaint(_StaticScissors old) => old.color != color;
}

/// The 5-second hook loop: a printed photo with the scarf cut out held over
/// fabric, then the same trick on a phone with fabrics changing behind it.
class HookAnimation extends StatefulWidget {
  const HookAnimation({super.key});

  @override
  State<HookAnimation> createState() => _HookAnimationState();
}

class _HookAnimationState extends State<HookAnimation> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 5));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _c.value = 0.8;
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(painter: _HookPainter(_c.value), size: Size.infinite),
      ),
    );
  }
}

class _HookPainter extends CustomPainter {
  _HookPainter(this.t);

  final double t;

  static const fabrics = [Color(0xFFB98C7B), Color(0xFF6E8B74), Color(0xFF5E6F8E), Color(0xFFC9A55A)];

  @override
  void paint(Canvas canvas, Size size) {
    // Background fabric (the store shelf), slowly shifting.
    final fabricIndex = t < 0.55 ? 0 : (1 + ((t - 0.55) / 0.15).floor()) % fabrics.length;
    final fabric = fabrics[fabricIndex];
    FigurePainter.paintFabric(canvas, Offset.zero & size, fabric, t * 3);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withValues(alpha: 0.12));

    final cardW = size.width * 0.56;
    final cardH = cardW * 1.3;
    final center = size.center(Offset.zero);
    final morph = Curves.easeInOutCubic.transform(((t - 0.32) / 0.18).clamp(0.0, 1.0));
    final rect = Rect.fromCenter(center: center, width: cardW, height: cardH * (1 + 0.32 * morph));
    final radius = Radius.circular(6 + 22 * morph);

    canvas.save();
    canvas.translate(0, math.sin(t * 2 * math.pi) * 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(2), radius).shift(const Offset(0, 8)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    final frameColor = Color.lerp(Colors.white, const Color(0xFF1B1A19), morph)!;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), Paint()..color = frameColor);
    final inner = rect.deflate(8 + 2 * morph);
    canvas.clipRRect(RRect.fromRectAndRadius(inner, Radius.circular(4 + 16 * morph)));
    canvas.translate(inner.left, inner.top);
    final cut = (t / 0.3).clamp(0.0, 1.0);
    FigurePainter(
      kind: FigureKind.hijab,
      fabric: t < 0.3 ? null : fabric,
      fabricPhase: t * 3,
      cutProgress: t < 0.3 ? cut : 1 - morph,
    ).paint(canvas, inner.size);
    canvas.restore();
    if (t < 0.3) {
      final win = FigurePainter(kind: FigureKind.hijab).window(inner.size);
      final metric = win.computeMetrics().first;
      final pos = metric.getTangentForOffset(metric.length * cut)?.position;
      if (pos != null) {
        ScissorsPainter.paintAt(canvas, inner.topLeft + pos, 26, 0.3 + 0.3 * math.sin(t * 60), Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(_HookPainter old) => old.t != t;
}
