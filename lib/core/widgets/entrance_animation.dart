import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/motion_policy.dart';

/// Fades and slides [child] up into place once, delayed by [index] for a
/// staggered list. Shows [child] straight away when motion is off.
class EntranceAnimation extends StatefulWidget {
  const EntranceAnimation({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 18,
    this.duration = const Duration(milliseconds: 420),
    this.stagger = const Duration(milliseconds: 55),
  });

  final Widget child;

  /// Position in the list; later items start a little later (capped).
  final int index;

  /// How far below its place the child starts, in logical pixels.
  final double offset;
  final Duration duration;
  final Duration stagger;

  @override
  State<EntranceAnimation> createState() => _EntranceAnimationState();
}

class _EntranceAnimationState extends State<EntranceAnimation>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Animation<double>? _curve;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null || !MotionPolicy.enabled(context)) return;
    final delay = widget.stagger * math.min(widget.index, 8);
    final total = delay + widget.duration;
    final c = AnimationController(vsync: this, duration: total);
    _c = c;
    _curve = CurvedAnimation(
      parent: c,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: Curves.easeOutCubic,
      ),
    );
    c.forward();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = _curve;
    if (curve == null) return widget.child;
    return AnimatedBuilder(
      animation: curve,
      child: widget.child,
      builder: (context, child) {
        final v = curve.value;
        if (v >= 1) return child!;
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * widget.offset),
            child: child,
          ),
        );
      },
    );
  }
}

/// Gently bobs [child] up and down on a loop (a floating envelope).
class Bobbing extends StatefulWidget {
  const Bobbing({
    super.key,
    required this.child,
    this.amplitude = 6,
    this.duration = const Duration(milliseconds: 3200),
    this.phase = 0,
    this.tilt = 0,
  });

  final Widget child;

  /// Peak offset in logical pixels.
  final double amplitude;
  final Duration duration;

  /// 0–1, so neighbours don't bob in step.
  final double phase;

  /// Peak rotation in radians, swaying with the bob.
  final double tilt;

  @override
  State<Bobbing> createState() => _BobbingState();
}

class _BobbingState extends State<Bobbing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.phase % 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MotionPolicy.enabled(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!MotionPolicy.enabled(context)) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final s = math.sin(_c.value * 2 * math.pi);
        return Transform.translate(
          offset: Offset(0, s * widget.amplitude),
          child: widget.tilt == 0
              ? child
              : Transform.rotate(angle: s * widget.tilt, child: child),
        );
      },
    );
  }
}

/// A looping 0→1→0 value for glows and pulsing dots. [builder] gets the
/// current value (0 when motion is off) and the unchanging [child].
class Pulse extends StatefulWidget {
  const Pulse({
    super.key,
    required this.builder,
    this.child,
    this.duration = const Duration(milliseconds: 1800),
  });

  final Widget Function(BuildContext context, double value, Widget? child)
  builder;
  final Widget? child;
  final Duration duration;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MotionPolicy.enabled(context)) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) =>
          widget.builder(context, Curves.easeInOut.transform(_c.value), child),
    );
  }
}
