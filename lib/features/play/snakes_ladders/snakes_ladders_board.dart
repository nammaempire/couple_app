import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:couple_app/features/play/dice/game_dice.dart';
import 'package:couple_app/features/play/snakes_ladders/snakes_ladders_logic.dart';

/// One player's token on the board.
class SnakesLaddersToken {
  const SnakesLaddersToken({
    required this.uid,
    required this.color,
    required this.face,
  });

  final String uid;

  /// Ring colour, so the two tokens are told apart at a glance.
  final Color color;

  /// What's inside the ring: the player's avatar or photo.
  final Widget face;
}

/// Board coordinates, in squares: (0, 0) is the top-left corner and the
/// board is 10 × 10.
class SnakesLaddersGeometry {
  const SnakesLaddersGeometry._();

  /// The centre of square [n]. Square 0 (not on the board yet) sits just
  /// left of square 1.
  static Offset centre(int n) {
    if (n <= 0) return const Offset(0.18, 9.62);
    final (row, col) = SnakesLaddersLogic.cellOf(n);
    return Offset(col + 0.5, SnakesLaddersLogic.size - row - 0.5);
  }

  /// Points along a snake's body, from its head to its tail: a gentle S
  /// bend so it reads as a snake rather than a line.
  static List<Offset> snakeSpine(int head, int tail, {int samples = 48}) {
    final a = centre(head);
    final b = centre(tail);
    final d = b - a;
    final len = d.distance;
    final normal = len == 0 ? Offset.zero : Offset(-d.dy, d.dx) / len;
    final bend = math.min(0.9, 0.25 + len * 0.12) * (head.isEven ? 1 : -1);
    final c1 = a + d * 0.3 + normal * bend;
    final c2 = a + d * 0.7 - normal * bend;
    return [
      for (var i = 0; i <= samples; i++) _cubic(a, c1, c2, b, i / samples),
    ];
  }

  static Offset _cubic(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final u = 1 - t;
    return p0 * (u * u * u) +
        p1 * (3 * u * u * t) +
        p2 * (3 * u * t * t) +
        p3 * (t * t * t);
  }

  /// The point a fraction [f] of the way along [points].
  static Offset along(List<Offset> points, double f) {
    if (points.length == 1) return points.first;
    final x = f.clamp(0.0, 1.0) * (points.length - 1);
    final i = x.floor().clamp(0, points.length - 2);
    return Offset.lerp(points[i], points[i + 1], x - i)!;
  }
}

/// The 10 × 10 board with both tokens.
///
/// When [moveKey] changes and [lastRoll] moved a token, that token walks
/// square by square (after the die has had [GameDice.rollDuration] to
/// land), then climbs the ladder or slides down the snake. Both phones
/// animate from the stored roll, so the partner sees the same journey.
class SnakesLaddersBoard extends StatefulWidget {
  const SnakesLaddersBoard({
    super.key,
    required this.positions,
    required this.tokens,
    this.lastRoll,
    this.moveKey = 0,
  });

  /// `{uid: square}`.
  final Map<String, int> positions;
  final List<SnakesLaddersToken> tokens;
  final SnakesLaddersRoll? lastRoll;
  final int moveKey;

  static const hop = Duration(milliseconds: 170);
  static const slide = Duration(milliseconds: 750);

  @override
  State<SnakesLaddersBoard> createState() => _SnakesLaddersBoardState();
}

class _SnakesLaddersBoardState extends State<SnakesLaddersBoard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this);
  _Journey? _journey;

  @override
  void didUpdateWidget(SnakesLaddersBoard old) {
    super.didUpdateWidget(old);
    final roll = widget.lastRoll;
    if (widget.moveKey != old.moveKey &&
        roll != null &&
        !roll.forfeit &&
        roll.from != roll.to) {
      final j = _Journey(roll);
      _journey = j;
      _anim
        ..duration = j.total
        ..forward(from: 0).whenCompleteOrCancel(() {
          if (mounted && _journey == j) setState(() => _journey = null);
        });
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        final cell = side / SnakesLaddersLogic.size;
        final tokenSize = cell * 0.72;
        return Center(
          child: SizedBox.square(
            dimension: side,
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, _) {
                final points = <String, Offset>{
                  for (final t in widget.tokens)
                    t.uid: _journey != null && _journey!.roll.by == t.uid
                        ? _journey!.at(_anim.value)
                        : SnakesLaddersGeometry.centre(
                            widget.positions[t.uid] ?? 0,
                          ),
                };
                // Two tokens on one square stand side by side.
                if (widget.tokens.length == 2) {
                  final a = widget.tokens[0].uid;
                  final b = widget.tokens[1].uid;
                  if ((points[a]! - points[b]!).distance < 0.3) {
                    points[a] = points[a]! - const Offset(0.2, 0.08);
                    points[b] = points[b]! + const Offset(0.2, 0.08);
                  }
                }
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: SnakesLaddersPainter(
                            scheme: theme.colorScheme,
                            dark: theme.brightness == Brightness.dark,
                            labelStyle: theme.textTheme.labelSmall,
                          ),
                        ),
                      ),
                    ),
                    for (final t in widget.tokens)
                      Positioned(
                        key: ValueKey('snl-token-${t.uid}'),
                        left: points[t.uid]!.dx * cell - tokenSize / 2,
                        top: points[t.uid]!.dy * cell - tokenSize / 2,
                        width: tokenSize,
                        height: tokenSize,
                        child: Opacity(
                          opacity:
                              (widget.positions[t.uid] ?? 0) == 0 &&
                                  _journey?.roll.by != t.uid
                              ? 0.75
                              : 1,
                          child: _TokenView(token: t, size: tokenSize),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// One roll's path for a token: wait for the die, hop square by square,
/// then ride the ladder or snake.
class _Journey {
  _Journey(this.roll) {
    final move = roll.move;
    _stops = [
      SnakesLaddersGeometry.centre(move.from),
      for (final s in move.steps) SnakesLaddersGeometry.centre(s),
    ];
    final via = roll.via;
    final from = roll.viaFrom;
    final to = roll.viaTo;
    if (from != null && to != null) {
      _ride = via == SnakesLaddersVia.snake
          ? SnakesLaddersGeometry.snakeSpine(from, to)
          : [
              SnakesLaddersGeometry.centre(from),
              SnakesLaddersGeometry.centre(to),
            ];
    }
    total =
        GameDice.rollDuration +
        SnakesLaddersBoard.hop * (_stops.length - 1) +
        (_ride == null ? Duration.zero : SnakesLaddersBoard.slide);
  }

  final SnakesLaddersRoll roll;
  late final List<Offset> _stops;
  List<Offset>? _ride;
  late final Duration total;

  Offset at(double t) {
    final ms = t * total.inMilliseconds;
    var rest = ms - GameDice.rollDuration.inMilliseconds;
    if (rest <= 0) return _stops.first;
    final hopMs = SnakesLaddersBoard.hop.inMilliseconds;
    final walk = (_stops.length - 1) * hopMs;
    if (rest < walk) {
      final i = rest ~/ hopMs;
      final f = (rest - i * hopMs) / hopMs;
      final p = Offset.lerp(_stops[i], _stops[i + 1], f)!;
      // A little hop on each step.
      return p - Offset(0, math.sin(f * math.pi) * 0.28);
    }
    rest -= walk;
    final ride = _ride;
    if (ride == null) return _stops.last;
    final f = Curves.easeInOut.transform(
      (rest / SnakesLaddersBoard.slide.inMilliseconds).clamp(0.0, 1.0),
    );
    return SnakesLaddersGeometry.along(ride, f);
  }
}

class _TokenView extends StatelessWidget {
  const _TokenView({required this.token, required this.size});

  final SnakesLaddersToken token;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: token.color, width: math.max(2, size * .09)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(child: FittedBox(child: token.face)),
    );
  }
}

/// Paints the squares, numbers, ladders and snakes.
class SnakesLaddersPainter extends CustomPainter {
  const SnakesLaddersPainter({
    required this.scheme,
    required this.dark,
    this.labelStyle,
  });

  final ColorScheme scheme;
  final bool dark;

  /// The app's text style for the square numbers (a painter doesn't
  /// inherit one, so it would otherwise fall back to a bare default font).
  final TextStyle? labelStyle;

  static const snakeColors = [
    Color(0xFF5FAE57),
    Color(0xFF9B6AD8),
    Color(0xFFE38B3B),
    Color(0xFF35A79E),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.shortestSide / SnakesLaddersLogic.size;
    Offset px(Offset u) => u * cell;

    final board = RRect.fromRectAndRadius(
      Offset.zero & Size.square(size.shortestSide),
      Radius.circular(cell * 0.35),
    );
    canvas.save();
    canvas.clipRRect(board);

    final a = Color.lerp(scheme.primaryContainer, scheme.surface, .45)!;
    final b = Color.lerp(scheme.tertiaryContainer, scheme.surface, .4)!;
    final fill = Paint();
    for (var n = 1; n <= SnakesLaddersLogic.last; n++) {
      final (row, col) = SnakesLaddersLogic.cellOf(n);
      fill.color = n == SnakesLaddersLogic.last
          ? scheme.primaryContainer
          : (row + col).isEven
          ? a
          : b;
      canvas.drawRect(
        Rect.fromLTWH(
          col * cell,
          (SnakesLaddersLogic.size - 1 - row) * cell,
          cell,
          cell,
        ),
        fill,
      );
      final label = TextPainter(
        text: TextSpan(
          text: n == SnakesLaddersLogic.last ? '100 🏁' : '$n',
          style: (labelStyle ?? const TextStyle()).copyWith(
            fontSize: cell * 0.24,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(
          col * cell + cell * 0.07,
          (SnakesLaddersLogic.size - 1 - row) * cell + cell * 0.04,
        ),
      );
    }
    canvas.restore();

    _ladders(canvas, cell, px);
    var i = 0;
    for (final e in SnakesLaddersLogic.snakes.entries) {
      _snake(canvas, cell, e.key, e.value, snakeColors[i++ % 4]);
    }

    canvas.drawRRect(
      board.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = scheme.outlineVariant,
    );
  }

  void _ladders(Canvas canvas, double cell, Offset Function(Offset) px) {
    final wood = dark ? const Color(0xFFD7A878) : const Color(0xFFA9744A);
    final rail = Paint()
      ..color = wood
      ..strokeWidth = cell * 0.075
      ..strokeCap = StrokeCap.round;
    final rung = Paint()
      ..color = wood.withValues(alpha: 0.9)
      ..strokeWidth = cell * 0.06
      ..strokeCap = StrokeCap.round;
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: dark ? 0.35 : 0.14)
      ..strokeWidth = cell * 0.1
      ..strokeCap = StrokeCap.round;
    for (final e in SnakesLaddersLogic.ladders.entries) {
      final foot = SnakesLaddersGeometry.centre(e.key);
      final top = SnakesLaddersGeometry.centre(e.value);
      final d = top - foot;
      final len = d.distance;
      final dir = d / len;
      final n = Offset(-dir.dy, dir.dx) * 0.17;
      // Run a little past each centre so the ends sit on the squares.
      final f = foot - dir * 0.18;
      final t = top + dir * 0.18;
      for (final side in [n, -n]) {
        canvas.drawLine(
          px(f + side + const Offset(0.03, 0.04)),
          px(t + side + const Offset(0.03, 0.04)),
          shadow,
        );
      }
      for (final side in [n, -n]) {
        canvas.drawLine(px(f + side), px(t + side), rail);
      }
      final rungs = (len / 0.34).floor();
      for (var k = 1; k <= rungs; k++) {
        final p = Offset.lerp(f, t, k / (rungs + 1))!;
        canvas.drawLine(px(p + n), px(p - n), rung);
      }
    }
  }

  void _snake(Canvas canvas, double cell, int head, int tail, Color color) {
    final spine = [
      for (final p in SnakesLaddersGeometry.snakeSpine(head, tail)) p * cell,
    ];
    final last = spine.length - 1;
    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i <= last; i++) {
      final prev = spine[math.max(0, i - 1)];
      final next = spine[math.min(last, i + 1)];
      final d = next - prev;
      final len = d.distance == 0 ? 1.0 : d.distance;
      final normal = Offset(-d.dy, d.dx) / len;
      // Thick behind the head, tapering to a point at the tail.
      final f = i / last;
      final w =
          cell *
          (0.11 + 0.07 * math.sin(math.min(1, f * 4) * math.pi / 2)) *
          (1 - f * 0.92);
      left.add(spine[i] + normal * w);
      right.add(spine[i] - normal * w);
    }
    final body = Path()..moveTo(left.first.dx, left.first.dy);
    for (final p in left.skip(1)) {
      body.lineTo(p.dx, p.dy);
    }
    for (final p in right.reversed) {
      body.lineTo(p.dx, p.dy);
    }
    body.close();

    final darker = Color.lerp(color, Colors.black, 0.35)!;
    canvas.drawPath(
      body.shift(Offset(cell * 0.03, cell * 0.05)),
      Paint()..color = Colors.black.withValues(alpha: dark ? 0.35 : 0.14),
    );
    canvas.drawPath(body, Paint()..color = color);
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.025
        ..color = darker,
    );
    // Spots down its back.
    final spot = Paint()..color = Color.lerp(color, Colors.white, 0.45)!;
    for (var i = 6; i < last - 4; i += 5) {
      canvas.drawCircle(spine[i], cell * 0.035 * (1 - i / last * 0.7), spot);
    }

    // The head points away from the body.
    final h = spine.first;
    final back = spine[3] - h;
    final ahead = -back / back.distance;
    final side = Offset(-ahead.dy, ahead.dx);
    canvas.save();
    canvas.translate(h.dx, h.dy);
    canvas.rotate(math.atan2(ahead.dy, ahead.dx));
    final headRect = Rect.fromCenter(
      center: Offset(cell * 0.04, 0),
      width: cell * 0.42,
      height: cell * 0.32,
    );
    canvas.drawOval(headRect, Paint()..color = color);
    canvas.drawOval(
      headRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.025
        ..color = darker,
    );
    canvas.restore();

    final tongue = Paint()
      ..color = const Color(0xFFE5484D)
      ..strokeWidth = cell * 0.025
      ..strokeCap = StrokeCap.round;
    final tip = h + ahead * cell * 0.36;
    canvas.drawLine(h + ahead * cell * 0.24, tip, tongue);
    canvas.drawLine(tip, tip + (ahead + side * 0.7) * cell * 0.06, tongue);
    canvas.drawLine(tip, tip + (ahead - side * 0.7) * cell * 0.06, tongue);

    for (final s in [1.0, -1.0]) {
      final eye = h + ahead * cell * 0.08 + side * (s * cell * 0.08);
      canvas.drawCircle(eye, cell * 0.045, Paint()..color = Colors.white);
      canvas.drawCircle(
        eye + ahead * cell * 0.012,
        cell * 0.022,
        Paint()..color = const Color(0xFF1D1B1C),
      );
    }
  }

  @override
  bool shouldRepaint(SnakesLaddersPainter old) =>
      old.scheme != scheme || old.dark != dark || old.labelStyle != labelStyle;
}
