import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/core/widgets/motion_policy.dart';

/// A rounded card whose gradient slowly drifts, with an occasional soft
/// sheen and gentle press feedback.
///
/// The gradient is painted by a [CustomPainter] that listens to the
/// controller directly, so [child] is never rebuilt on a tick. Motion stops
/// when [MotionPolicy] says so (reduced motion, tests) and pauses with
/// [TickerMode] (off-screen tabs and routes).
class AnimatedGradientCard extends StatefulWidget {
  const AnimatedGradientCard({
    super.key,
    required this.child,
    this.preset = GradientPreset.blush,
    this.colors,
    this.onTap,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
    this.animate = true,
    this.sheen = true,
    this.shadow = true,
    this.glow,
    this.border,
    this.duration = const Duration(seconds: 8),
  });

  final Widget child;

  /// The palette; [colors] overrides it when given.
  final GradientPreset preset;
  final List<Color>? colors;

  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Drift the gradient. Off keeps a still gradient.
  final bool animate;

  /// Sweep a soft highlight across every few seconds.
  final bool sheen;

  /// Soft coloured drop shadow.
  final bool shadow;

  /// An extra coloured halo, e.g. for unread items.
  final Color? glow;

  final BoxBorder? border;

  /// One full drift cycle.
  final Duration duration;

  @override
  State<AnimatedGradientCard> createState() => _AnimatedGradientCardState();
}

class _AnimatedGradientCardState extends State<AnimatedGradientCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  bool _pressed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(AnimatedGradientCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _drift.duration = widget.duration;
    }
    _sync();
  }

  void _sync() {
    final run = widget.animate && MotionPolicy.enabled(context);
    if (run && !_drift.isAnimating) {
      _drift.repeat();
    } else if (!run && _drift.isAnimating) {
      _drift
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final colors = widget.colors ?? widget.preset.colors(brightness);
    final radius = BorderRadius.circular(widget.radius);
    final moving = widget.animate && MotionPolicy.enabled(context);

    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          if (widget.shadow)
            BoxShadow(
              color: widget.preset.shadow(brightness),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          if (widget.glow != null)
            BoxShadow(
              color: widget.glow!.withValues(alpha: .35),
              blurRadius: 22,
              spreadRadius: 1,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: GradientDriftPainter(
                    colors: colors,
                    progress: _drift,
                    sheen: widget.sheen && moving,
                  ),
                ),
              ),
            ),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onTap,
                onHighlightChanged: widget.onTap == null
                    ? null
                    : (v) => setState(() => _pressed = v),
                borderRadius: radius,
                child: Container(
                  padding: widget.padding,
                  decoration: widget.border == null
                      ? null
                      : BoxDecoration(
                          borderRadius: radius,
                          border: widget.border,
                        ),
                  child: widget.child,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.onTap != null) {
      card = AnimatedScale(
        scale: _pressed ? .98 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: card,
      );
    }
    return card;
  }
}

/// A full-bleed drifting gradient, for page backgrounds.
class AnimatedGradientBackground extends StatelessWidget {
  const AnimatedGradientBackground({
    super.key,
    this.preset = GradientPreset.blush,
    this.colors,
    this.child = const SizedBox.expand(),
    this.duration = const Duration(seconds: 10),
  });

  final GradientPreset preset;
  final List<Color>? colors;
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedGradientCard(
      preset: preset,
      colors: colors,
      radius: 0,
      shadow: false,
      sheen: false,
      padding: EdgeInsets.zero,
      duration: duration,
      child: child,
    );
  }
}

/// Paints [colors] as a linear gradient whose angle sways and whose middle
/// stop drifts with [progress], plus an optional diagonal sheen.
class GradientDriftPainter extends CustomPainter {
  GradientDriftPainter({
    required this.colors,
    required this.progress,
    this.sheen = false,
  }) : super(repaint: progress);

  final List<Color> colors;
  final Animation<double> progress;
  final bool sheen;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final t = progress.value * 2 * math.pi;
    final angle = math.pi / 4 + .55 * math.sin(t);
    final dx = math.cos(angle);
    final dy = math.sin(angle);
    final stops = colors.length == 3
        ? [0.0, .5 + .18 * math.sin(t + 1.3), 1.0]
        : null;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-dx, -dy),
          end: Alignment(dx, dy),
          colors: colors,
          stops: stops,
        ).createShader(rect),
    );

    if (!sheen) return;
    // Two sweeps per cycle, each over the first 30% of its half.
    final phase = (progress.value * 2) % 1;
    if (phase > .3) return;
    final x = -.4 + (phase / .3) * 1.8;
    final band = Rect.fromLTWH(
      size.width * (x - .25),
      0,
      size.width * .5,
      size.height,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          transform: const GradientRotation(-.35),
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: .22),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(band),
    );
  }

  @override
  bool shouldRepaint(GradientDriftPainter oldDelegate) =>
      oldDelegate.colors != colors ||
      oldDelegate.sheen != sheen ||
      oldDelegate.progress != progress;
}
