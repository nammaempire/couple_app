import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/motion_policy.dart';

/// The shapes [FloatingHearts] draws.
enum ParticleStyle {
  /// Hearts with a few sparkles.
  hearts,

  /// Twinkling stars that drift slowly (for night themes).
  stars,

  /// Confetti-coloured sparkles and hearts (for celebrations).
  confetti,
}

/// A background layer of a few slow-rising translucent hearts or sparkles.
///
/// Draws nothing when motion is off ([MotionPolicy]), and pauses with
/// [TickerMode]. Never intercepts touches.
class FloatingHearts extends StatefulWidget {
  const FloatingHearts({
    super.key,
    this.color = Colors.white,
    this.count = 14,
    this.style = ParticleStyle.hearts,
    this.seed = 7,
    this.duration = const Duration(seconds: 14),
    this.opacity = .55,
  });

  final Color color;
  final int count;
  final ParticleStyle style;
  final int seed;
  final Duration duration;

  /// Peak opacity of a particle.
  final double opacity;

  @override
  State<FloatingHearts> createState() => _FloatingHeartsState();
}

class _FloatingHeartsState extends State<FloatingHearts>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late List<_Particle> _particles = _make();

  List<_Particle> _make() {
    final r = math.Random(widget.seed);
    return [
      for (var i = 0; i < widget.count; i++)
        _Particle(
          x: r.nextDouble(),
          phase: r.nextDouble(),
          speed: .6 + r.nextDouble() * .7,
          size: 8 + r.nextDouble() * 14,
          sway: 6 + r.nextDouble() * 14,
          kind: switch (widget.style) {
            ParticleStyle.hearts => r.nextDouble() < .75 ? 0 : 1,
            ParticleStyle.stars => r.nextDouble() < .8 ? 2 : 1,
            ParticleStyle.confetti => r.nextInt(3),
          },
          hue: r.nextInt(5),
        ),
    ];
  }

  @override
  void didUpdateWidget(FloatingHearts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count ||
        oldWidget.seed != widget.seed ||
        oldWidget.style != widget.style) {
      _particles = _make();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MotionPolicy.enabled(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      // Frozen (tests, screenshots): one still frame.
      _c
        ..stop()
        ..value = .37;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MotionPolicy.systemReduced(context)) return const SizedBox.expand();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _HeartsPainter(
            progress: _c,
            particles: _particles,
            color: widget.color,
            style: widget.style,
            opacity: widget.opacity,
          ),
        ),
      ),
    );
  }
}

class _Particle {
  const _Particle({
    required this.x,
    required this.phase,
    required this.speed,
    required this.size,
    required this.sway,
    required this.kind,
    required this.hue,
  });

  final double x;
  final double phase;
  final double speed;
  final double size;
  final double sway;

  /// 0 heart, 1 sparkle, 2 star dot.
  final int kind;
  final int hue;
}

const _confetti = [
  Color(0xFFFF6FA5),
  Color(0xFFFFC94D),
  Color(0xFF8E7CFF),
  Color(0xFF4DD0B5),
  Color(0xFFFF8A65),
];

class _HeartsPainter extends CustomPainter {
  _HeartsPainter({
    required this.progress,
    required this.particles,
    required this.color,
    required this.style,
    required this.opacity,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final List<_Particle> particles;
  final Color color;
  final ParticleStyle style;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    for (final p in particles) {
      final paint = Paint()..isAntiAlias = true;
      final base = style == ParticleStyle.confetti ? _confetti[p.hue] : color;
      if (style == ParticleStyle.stars) {
        // Stars hang in place and twinkle, drifting up very slowly.
        final y = ((p.phase - t * .08 * p.speed) % 1) * size.height;
        final x = p.x * size.width;
        final tw =
            .35 +
            .65 *
                (.5 + .5 * math.sin((t * p.speed * 6 + p.phase) * 2 * math.pi));
        paint.color = base.withValues(alpha: opacity * tw);
        if (p.kind == 2) {
          canvas.drawCircle(Offset(x, y), p.size * .12, paint);
        } else {
          _sparkle(canvas, Offset(x, y), p.size * .55, paint);
        }
        continue;
      }
      final life = (p.phase + t * p.speed) % 1;
      final y = size.height * (1.05 - life * 1.15);
      final x =
          p.x * size.width +
          math.sin((life * 2 + p.phase) * 2 * math.pi) * p.sway;
      // Fade in at the bottom, out at the top.
      final fade = math.min(1.0, math.min(life / .15, (1 - life) / .35));
      paint.color = base.withValues(alpha: opacity * fade.clamp(0, 1));
      if (p.kind == 0) {
        _heart(canvas, Offset(x, y), p.size, paint);
      } else {
        _sparkle(canvas, Offset(x, y), p.size * .6, paint);
      }
    }
  }

  static void _heart(Canvas canvas, Offset c, double s, Paint paint) {
    final w = s;
    final h = s;
    final path = Path()
      ..moveTo(c.dx, c.dy + h * .35)
      ..cubicTo(
        c.dx - w * .9,
        c.dy - h * .15,
        c.dx - w * .45,
        c.dy - h * .75,
        c.dx,
        c.dy - h * .3,
      )
      ..cubicTo(
        c.dx + w * .45,
        c.dy - h * .75,
        c.dx + w * .9,
        c.dy - h * .15,
        c.dx,
        c.dy + h * .35,
      )
      ..close();
    canvas.drawPath(path, paint);
  }

  static void _sparkle(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_HeartsPainter oldDelegate) =>
      oldDelegate.particles != particles ||
      oldDelegate.color != color ||
      oldDelegate.style != style ||
      oldDelegate.opacity != opacity;
}
