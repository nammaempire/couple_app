import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A die that tumbles when rolled and then shows [value].
///
/// It tumbles for about [rollDuration] whenever [rollId] changes (a new
/// roll arrived, on either phone), and keeps tumbling while [rolling] is
/// true (my roll is on its way). Tapping it calls [onRoll] with a haptic
/// bump; a null [onRoll] makes it read-only.
class GameDice extends StatefulWidget {
  const GameDice({
    super.key,
    this.value,
    this.rollId,
    this.rolling = false,
    this.size = 56,
    this.accent,
    this.onRoll,
  });

  /// The face to show when still; null shows a blank face.
  final int? value;

  /// Identifies the current roll; a change replays the tumble.
  final Object? rollId;

  /// Tumble until this turns false.
  final bool rolling;
  final double size;

  /// Glow colour while it can be tapped.
  final Color? accent;
  final VoidCallback? onRoll;

  static const rollDuration = Duration(milliseconds: 600);

  @override
  State<GameDice> createState() => _GameDiceState();
}

class _GameDiceState extends State<GameDice>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: GameDice.rollDuration,
  );

  @override
  void initState() {
    super.initState();
    if (widget.rolling) _spin.repeat();
  }

  @override
  void didUpdateWidget(GameDice old) {
    super.didUpdateWidget(old);
    if (widget.rollId != old.rollId && widget.rollId != null) {
      _spin.forward(from: 0).whenCompleteOrCancel(() {
        if (mounted && !widget.rolling) HapticFeedback.selectionClick();
      });
    } else if (widget.rolling && !old.rolling) {
      _spin.repeat();
    } else if (!widget.rolling && old.rolling && _spin.isAnimating) {
      // The roll failed: settle back on the old face.
      _spin.forward();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _tap() {
    HapticFeedback.mediumImpact();
    widget.onRoll?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final enabled = widget.onRoll != null;
    final accent = widget.accent ?? scheme.primary;
    return Semantics(
      button: enabled,
      label: widget.value == null ? 'Die' : 'Die showing ${widget.value}',
      child: GestureDetector(
        key: const ValueKey('dice-roll'),
        onTap: enabled ? _tap : null,
        child: AnimatedBuilder(
          animation: _spin,
          builder: (context, _) {
            final t = _spin.value;
            final moving = _spin.isAnimating;
            // Cycle through faces while tumbling; deterministic so the
            // animation is the same on both phones.
            final face = moving
                ? ((t * 14).floor() + (widget.value ?? 3)) % 6 + 1
                : widget.value;
            final turns = Curves.easeOutCubic.transform(moving ? t : 1);
            final hop = moving ? math.sin(t * math.pi) * widget.size * 0.18 : 0;
            return Transform.translate(
              offset: Offset(0, -hop.toDouble()),
              child: Transform.rotate(
                angle: turns * math.pi * 2,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.size * 0.24),
                    boxShadow: [
                      if (enabled)
                        BoxShadow(
                          color: accent.withValues(alpha: 0.45),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: dark ? .4 : .12),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: CustomPaint(
                    painter: DicePainter(
                      value: face,
                      face: dark
                          ? scheme.surfaceContainerHighest
                          : Colors.white,
                      pip: dark ? scheme.onSurface : const Color(0xFF2B2124),
                      edge: enabled ? accent : scheme.outlineVariant,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Paints one die face with [value] pips (none when null).
class DicePainter extends CustomPainter {
  const DicePainter({
    required this.value,
    required this.face,
    required this.pip,
    required this.edge,
  });

  final int? value;
  final Color face;
  final Color pip;
  final Color edge;

  /// Pip centres on a 3×3 grid (0..2), per face.
  static const pips = <int, List<(int, int)>>{
    1: [(1, 1)],
    2: [(0, 0), (2, 2)],
    3: [(0, 0), (1, 1), (2, 2)],
    4: [(0, 0), (2, 0), (0, 2), (2, 2)],
    5: [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)],
    6: [(0, 0), (2, 0), (0, 1), (2, 1), (0, 2), (2, 2)],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final rect = Offset.zero & Size.square(s);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(s * 0.24));
    canvas.drawRRect(rrect, Paint()..color = face);
    canvas.drawRRect(
      rrect.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = edge.withValues(alpha: 0.7),
    );
    final dots = pips[value] ?? const [];
    final r = s * 0.085;
    final paint = Paint()..color = pip;
    for (final (x, y) in dots) {
      canvas.drawCircle(
        Offset(s * (0.25 + x * 0.25), s * (0.25 + y * 0.25)),
        r,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(DicePainter old) =>
      old.value != value ||
      old.face != face ||
      old.pip != pip ||
      old.edge != edge;
}
