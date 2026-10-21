import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:couple_app/features/play/ludo/ludo_geometry.dart';
import 'package:couple_app/features/play/ludo/ludo_logic.dart';

/// One player's side of the board.
class LudoSide {
  const LudoSide({required this.uid, required this.seat, required this.tokens});

  final String uid;

  /// [LudoLogic.red] or [LudoLogic.yellow].
  final int seat;

  /// Progress of each token, in the owner's frame.
  final List<int> tokens;
}

/// The cross-shaped board with both players' tokens.
///
/// [movable] tokens of [myUid] pulse and can be tapped. When [moveKey]
/// changes and [lastRoll] moved a token, it walks square by square; a
/// capture bursts on the square before the captured token goes home.
class LudoBoard extends StatefulWidget {
  const LudoBoard({
    super.key,
    required this.sides,
    required this.myUid,
    this.movable = const [],
    this.onTapToken,
    this.lastRoll,
    this.moveKey = 0,
  });

  final List<LudoSide> sides;
  final String myUid;
  final List<int> movable;
  final ValueChanged<int>? onTapToken;
  final LudoRoll? lastRoll;
  final int moveKey;

  static const hop = Duration(milliseconds: 150);
  static const burst = Duration(milliseconds: 520);

  static const seatColors = [
    Color(0xFFE5484D),
    Color(0xFF3FA36B),
    Color(0xFFF2B40F),
    Color(0xFF3D7FD9),
  ];

  @override
  State<LudoBoard> createState() => _LudoBoardState();
}

class _LudoBoardState extends State<LudoBoard> with TickerProviderStateMixin {
  late final AnimationController _move = AnimationController(vsync: this);
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  _Walk? _walk;

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(LudoBoard old) {
    super.didUpdateWidget(old);
    final roll = widget.lastRoll;
    if (widget.moveKey != old.moveKey && roll != null && roll.moved) {
      final side = widget.sides.where((s) => s.uid == roll.by).firstOrNull;
      if (side != null) {
        final walk = _Walk(roll, side.seat);
        _walk = walk;
        _move
          ..duration = walk.total
          ..forward(from: 0).whenCompleteOrCancel(() {
            if (mounted && _walk == walk) setState(() => _walk = null);
          });
      }
    }
    _syncPulse();
  }

  void _syncPulse() {
    final pulsing = widget.movable.isNotEmpty && widget.onTapToken != null;
    if (pulsing && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!pulsing && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _move.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = {for (final s in widget.sides) s.seat};
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        final cell = side / LudoGeometry.grid;
        return Center(
          child: SizedBox.square(
            dimension: side,
            child: AnimatedBuilder(
              animation: Listenable.merge([_move, _pulse]),
              builder: (context, _) => Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: LudoPainter(
                          scheme: theme.colorScheme,
                          dark: theme.brightness == Brightness.dark,
                          activeSeats: active,
                        ),
                      ),
                    ),
                  ),
                  ..._tokens(cell),
                  ?_burst(cell),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _tokens(double cell) {
    final walk = _walk;
    final t = _move.value;
    final placed = <_Placed>[];
    for (final s in widget.sides) {
      for (var i = 0; i < s.tokens.length; i++) {
        var p = LudoGeometry.tokenPoint(s.seat, s.tokens[i], i);
        var moving = false;
        if (walk != null) {
          if (s.uid == walk.roll.by && i == walk.roll.token) {
            p = walk.at(t);
            moving = true;
          } else if (s.uid != walk.roll.by &&
              walk.roll.captured.contains(i) &&
              !walk.bursting(t)) {
            // Still standing where it was caught.
            p = walk.end;
          }
        }
        placed.add(_Placed(s, i, p, moving));
      }
    }

    // Tokens sharing a square shrink and fan out.
    final groups = <String, List<_Placed>>{};
    for (final x in placed.where((x) => !x.moving)) {
      final key = '${(x.point.dx * 4).round()}:${(x.point.dy * 4).round()}';
      (groups[key] ??= []).add(x);
    }
    for (final g in groups.values) {
      if (g.length < 2) continue;
      for (var k = 0; k < g.length; k++) {
        final o = switch ((g.length, k)) {
          (2, 0) => const Offset(-0.2, 0),
          (2, _) => const Offset(0.2, 0),
          (_, 0) => const Offset(-0.2, -0.2),
          (_, 1) => const Offset(0.2, -0.2),
          (_, 2) => const Offset(-0.2, 0.2),
          (_, 3) => const Offset(0.2, 0.2),
          _ => Offset.zero,
        };
        g[k].point += o;
        g[k].scale = 0.7;
      }
    }

    // Mine on top, the mover above everything.
    placed.sort((a, b) {
      int rank(_Placed x) =>
          x.moving ? 2 : (x.side.uid == widget.myUid ? 1 : 0);
      return rank(a).compareTo(rank(b));
    });

    final pulse = Curves.easeInOut.transform(_pulse.value);
    return [
      for (final x in placed)
        _positioned(
          x,
          cell,
          selectable:
              x.side.uid == widget.myUid &&
              widget.onTapToken != null &&
              widget.movable.contains(x.index),
          pulse: pulse,
        ),
    ];
  }

  Widget _positioned(
    _Placed x,
    double cell, {
    required bool selectable,
    required double pulse,
  }) {
    final size = cell * 0.86 * x.scale * (selectable ? 1 + pulse * 0.12 : 1);
    final hit = math.max(size, cell);
    final mine = x.side.uid == widget.myUid;
    final pawn = _Pawn(
      color: LudoBoard.seatColors[x.side.seat],
      size: size,
      glow: selectable ? 0.35 + pulse * 0.5 : 0,
    );
    return Positioned(
      key: ValueKey('ludo-${mine ? 'my' : 'their'}-token-${x.index}'),
      left: x.point.dx * cell - hit / 2,
      top: x.point.dy * cell - hit / 2,
      width: hit,
      height: hit,
      child: selectable
          ? Semantics(
              button: true,
              label: 'Move token ${x.index + 1}',
              child: GestureDetector(
                key: ValueKey('ludo-token-${x.index}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onTapToken!(x.index),
                child: Center(child: pawn),
              ),
            )
          : IgnorePointer(child: Center(child: pawn)),
    );
  }

  Widget? _burst(double cell) {
    final walk = _walk;
    if (walk == null || walk.roll.captured.isEmpty) return null;
    final f = walk.burstProgress(_move.value);
    if (f <= 0 || f >= 1) return null;
    final size = cell * (0.8 + f * 1.6);
    return Positioned(
      left: walk.end.dx * cell - size / 2,
      top: walk.end.dy * cell - size / 2,
      width: size,
      height: size,
      child: IgnorePointer(
        child: Opacity(
          opacity: 1 - f,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: LudoBoard.seatColors[walk.seat],
                width: math.max(2, cell * 0.15 * (1 - f)),
              ),
            ),
            child: Text('💥', style: TextStyle(fontSize: cell * 0.8)),
          ),
        ),
      ),
    );
  }
}

class _Placed {
  _Placed(this.side, this.index, this.point, this.moving);

  final LudoSide side;
  final int index;
  Offset point;
  final bool moving;
  double scale = 1;
}

/// A token's trip for one move, then the capture burst.
class _Walk {
  _Walk(this.roll, this.seat)
    : _stops = LudoGeometry.path(seat, roll.token!, roll.from!, roll.to!) {
    _walkMs = (_stops.length - 1) * LudoBoard.hop.inMilliseconds;
    final burstMs = roll.captured.isEmpty ? 0 : LudoBoard.burst.inMilliseconds;
    total = Duration(milliseconds: math.max(1, _walkMs + burstMs));
  }

  final LudoRoll roll;
  final int seat;
  final List<Offset> _stops;
  late final int _walkMs;
  late final Duration total;

  Offset get end => _stops.last;

  Offset at(double t) {
    final ms = t * total.inMilliseconds;
    if (ms >= _walkMs) return end;
    final hop = LudoBoard.hop.inMilliseconds;
    final i = (ms ~/ hop).clamp(0, _stops.length - 2);
    final f = (ms - i * hop) / hop;
    return Offset.lerp(_stops[i], _stops[i + 1], f)! -
        Offset(0, math.sin(f * math.pi) * 0.35);
  }

  bool bursting(double t) => t * total.inMilliseconds >= _walkMs;

  double burstProgress(double t) {
    final ms = t * total.inMilliseconds - _walkMs;
    return ms <= 0 ? 0 : ms / LudoBoard.burst.inMilliseconds;
  }
}

class _Pawn extends StatelessWidget {
  const _Pawn({required this.color, required this.size, this.glow = 0});

  final Color color;
  final double size;
  final double glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [Color.lerp(color, Colors.white, 0.45)!, color],
        ),
        border: Border.all(
          color: Colors.white,
          width: math.max(1.5, size * .1),
        ),
        boxShadow: [
          if (glow > 0)
            BoxShadow(
              color: color.withValues(alpha: glow),
              blurRadius: size * 0.6,
              spreadRadius: size * 0.12,
            ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 3,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: size * 0.32,
          height: size * 0.32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.lerp(color, Colors.black, 0.25),
          ),
        ),
      ),
    );
  }
}

/// Paints the yards, track, home columns, safe squares and centre.
class LudoPainter extends CustomPainter {
  const LudoPainter({
    required this.scheme,
    required this.dark,
    required this.activeSeats,
  });

  final ColorScheme scheme;
  final bool dark;

  /// Seats in play; the others are drawn faded.
  final Set<int> activeSeats;

  Color _seat(int seat, {double strength = 1}) {
    final base = LudoBoard.seatColors[seat];
    final faded = activeSeats.contains(seat) ? 0.0 : 0.72;
    final surface = dark ? scheme.surfaceContainerHigh : scheme.surface;
    return Color.lerp(base, surface, 1 - strength * (1 - faded))!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.shortestSide / LudoGeometry.grid;
    final boardRect = Offset.zero & Size.square(size.shortestSide);
    final square = dark ? scheme.surfaceContainerHigh : scheme.surface;
    final line = scheme.outlineVariant.withValues(alpha: dark ? 0.6 : 0.9);
    final board = RRect.fromRectAndRadius(
      boardRect,
      Radius.circular(cell * 0.6),
    );
    canvas.save();
    canvas.clipRRect(board);
    canvas.drawRect(boardRect, Paint()..color = square);

    Rect cellRect((int, int) c) =>
        Rect.fromLTWH(c.$1 * cell, c.$2 * cell, cell, cell);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = line;

    // Yards: a coloured block with a pale inner court and four spots.
    for (var seat = 0; seat < 4; seat++) {
      final (x, y) = LudoGeometry.yards[seat];
      final outer = Rect.fromLTWH(x * cell, y * cell, cell * 6, cell * 6);
      canvas.drawRect(outer, Paint()..color = _seat(seat));
      final inner = RRect.fromRectAndRadius(
        outer.deflate(cell * 0.9),
        Radius.circular(cell * 0.7),
      );
      canvas.drawRRect(inner, Paint()..color = square);
      for (final slot in LudoGeometry.yardSlots) {
        final c = (Offset(x.toDouble(), y.toDouble()) + slot) * cell;
        canvas.drawCircle(
          c,
          cell * 0.55,
          Paint()..color = _seat(seat, strength: .3),
        );
        canvas.drawCircle(
          c,
          cell * 0.55,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * 0.06
            ..color = _seat(seat, strength: .8),
        );
      }
    }

    // Track squares, start squares in their colour, stars on the others.
    for (var i = 0; i < LudoGeometry.track.length; i++) {
      final r = cellRect(LudoGeometry.track[i]);
      final start = i % LudoLogic.seatOffset == 0;
      if (start) {
        canvas.drawRect(r, Paint()..color = _seat(i ~/ LudoLogic.seatOffset));
        _arrow(canvas, r, i ~/ LudoLogic.seatOffset);
      }
      canvas.drawRect(r, stroke);
      if (!start && LudoLogic.isSafe(i)) _star(canvas, r);
    }
    for (var seat = 0; seat < 4; seat++) {
      for (final c in LudoGeometry.homeColumns[seat]) {
        final r = cellRect(c);
        canvas.drawRect(r, Paint()..color = _seat(seat));
        canvas.drawRect(r, stroke);
      }
    }

    // Home: four triangles meeting in the middle.
    final mid = Offset(7.5, 7.5) * cell;
    final corners = [
      [const Offset(6, 6), const Offset(6, 9)],
      [const Offset(6, 6), const Offset(9, 6)],
      [const Offset(9, 6), const Offset(9, 9)],
      [const Offset(6, 9), const Offset(9, 9)],
    ];
    for (var seat = 0; seat < 4; seat++) {
      final a = corners[seat][0] * cell;
      final b = corners[seat][1] * cell;
      final tri = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(mid.dx, mid.dy)
        ..close();
      canvas.drawPath(tri, Paint()..color = _seat(seat));
      canvas.drawPath(tri, stroke);
    }
    canvas.restore();
    canvas.drawRRect(
      board.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = scheme.outline.withValues(alpha: 0.5),
    );
  }

  void _star(Canvas canvas, Rect r) {
    final c = r.center;
    final outer = r.width * 0.36;
    final inner = outer * 0.45;
    final path = Path();
    for (var k = 0; k < 10; k++) {
      final radius = k.isEven ? outer : inner;
      final a = -math.pi / 2 + k * math.pi / 5;
      final p = c + Offset(math.cos(a), math.sin(a)) * radius;
      k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()..color = scheme.onSurfaceVariant.withValues(alpha: 0.45),
    );
  }

  /// A small arrow on a start square, pointing the way play goes.
  void _arrow(Canvas canvas, Rect r, int seat) {
    final angle = switch (seat) {
      LudoLogic.red => 0.0,
      LudoLogic.green => math.pi / 2,
      LudoLogic.yellow => math.pi,
      _ => -math.pi / 2,
    };
    canvas.save();
    canvas.translate(r.center.dx, r.center.dy);
    canvas.rotate(angle);
    final s = r.width * 0.22;
    final path = Path()
      ..moveTo(s, 0)
      ..lineTo(-s * 0.6, -s * 0.8)
      ..lineTo(-s * 0.6, s * 0.8)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(LudoPainter old) =>
      old.scheme != scheme ||
      old.dark != dark ||
      old.activeSeats.length != activeSeats.length ||
      !old.activeSeats.containsAll(activeSeats);
}
