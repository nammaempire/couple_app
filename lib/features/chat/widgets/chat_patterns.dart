import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:couple_app/features/chat/models/chat_look.dart';

/// A built-in chat background, drawn in code by [ChatPatternPainter].
class ChatPattern {
  const ChatPattern(this.id, this.label);

  /// Stored in Firestore; never rename one.
  final String id;
  final String label;
}

/// The built-in backgrounds, in the order they are offered.
class ChatPatterns {
  const ChatPatterns._();

  static const all = [
    ChatPattern('hearts', 'Hearts'),
    ChatPattern('doodles', 'Doodles'),
    ChatPattern('dots', 'Dots'),
    ChatPattern('waves', 'Waves'),
    ChatPattern('confetti', 'Confetti'),
    ChatPattern('sunset', 'Sunset'),
    ChatPattern('ocean', 'Ocean'),
    ChatPattern('lavender', 'Lavender'),
    ChatPattern('blush', 'Blush'),
    ChatPattern('mint', 'Mint'),
  ];

  static ChatPattern? byId(String? id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  static bool isKnown(String? id) => byId(id) != null;

  /// Whether [background] actually draws something behind the messages.
  /// Unknown pattern ids (from a newer app version) count as none.
  static bool shows(ChatBackground background) =>
      background.isPhoto ||
      (background.isPattern && isKnown(background.patternId));
}

/// Paints a built-in pattern as vectors, so it is crisp at any pixel ratio.
///
/// Colours come from [scheme] and [background] (the chat's scaffold colour),
/// kept low-contrast so bubbles stay readable in light and dark.
class ChatPatternPainter extends CustomPainter {
  ChatPatternPainter({
    required this.patternId,
    required this.scheme,
    required this.background,
  });

  final String patternId;
  final ColorScheme scheme;
  final Color background;

  bool get _dark => scheme.brightness == Brightness.dark;

  Color _motif([double light = .10, double dark = .16]) =>
      scheme.primary.withValues(alpha: _dark ? dark : light);

  Color _tint(int argb, [double light = .26, double dark = .20]) =>
      Color.lerp(background, Color(argb), _dark ? dark : light)!;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas
      ..save()
      ..clipRect(rect)
      ..drawRect(rect, Paint()..color = background);
    switch (patternId) {
      case 'hearts':
        _hearts(canvas, size);
      case 'doodles':
        _doodles(canvas, size);
      case 'dots':
        _dots(canvas, size);
      case 'waves':
        _waves(canvas, size);
      case 'confetti':
        _confetti(canvas, size);
      case 'sunset':
        _gradient(canvas, rect, 0xFFFFB074, 0xFFF06292);
      case 'ocean':
        _gradient(canvas, rect, 0xFF4FC3F7, 0xFF26A69A);
      case 'lavender':
        _gradient(canvas, rect, 0xFFB39DDB, 0xFFF8BBD0);
      case 'blush':
        canvas.drawRect(rect, Paint()..color = _tint(0xFFF48FB1, .16, .12));
      case 'mint':
        canvas.drawRect(rect, Paint()..color = _tint(0xFF80CBC4, .18, .12));
    }
    canvas.restore();
  }

  /// Calls [paintTile] with the origin of every tile covering [size].
  /// Odd rows shift by [rowShift] for a staggered look.
  void _tiles(
    Size size,
    double w,
    double h,
    void Function(Offset origin, int row, int col) paintTile, {
    double rowShift = 0,
  }) {
    final rows = (size.height / h).ceil() + 1;
    final cols = (size.width / w).ceil() + 2;
    for (var r = 0; r < rows; r++) {
      final shift = r.isOdd ? rowShift : 0.0;
      for (var c = -1; c < cols; c++) {
        paintTile(Offset(c * w + shift, r * h), r, c);
      }
    }
  }

  void _hearts(Canvas canvas, Size size) {
    final paint = Paint()..color = _motif(.11, .17);
    _tiles(size, 48, 44, rowShift: 24, (o, r, c) {
      final angle = (r + c).isEven ? -.2 : .2;
      canvas
        ..save()
        ..translate(o.dx + 24, o.dy + 22)
        ..rotate(angle)
        ..drawPath(_heart(Offset.zero, 11), paint)
        ..restore();
    });
  }

  void _doodles(Canvas canvas, Size size) {
    final fill = Paint()..color = _motif(.11, .17);
    final stroke = Paint()
      ..color = _motif(.12, .18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    _tiles(size, 104, 104, (o, _, _) {
      canvas.drawPath(_heart(o + const Offset(18, 20), 12), fill);
      canvas.drawPath(_star(o + const Offset(66, 16), 6.5), fill);
      canvas.drawCircle(o + const Offset(90, 52), 4.5, stroke);
      canvas.drawPath(_squiggle(o + const Offset(30, 58), 22), stroke);
      canvas.drawPath(_star(o + const Offset(14, 88), 4.5), fill);
      canvas.drawPath(_heart(o + const Offset(70, 84), 9), fill);
      canvas.drawCircle(o + const Offset(48, 34), 2, fill);
    });
  }

  void _dots(Canvas canvas, Size size) {
    final paint = Paint()..color = _motif(.14, .20);
    _tiles(size, 20, 20, rowShift: 10, (o, _, _) {
      canvas.drawCircle(o + const Offset(10, 10), 1.8, paint);
    });
  }

  void _waves(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _motif(.12, .18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    const wavelength = 56.0;
    const amplitude = 5.0;
    const gap = 26.0;
    for (var y = gap / 2, row = 0; y < size.height + gap; y += gap, row++) {
      final path = Path();
      var x = row.isOdd ? -wavelength / 2 : -wavelength;
      path.moveTo(x, y);
      while (x < size.width + wavelength) {
        path
          ..quadraticBezierTo(
            x + wavelength / 4,
            y - amplitude,
            x + wavelength / 2,
            y,
          )
          ..quadraticBezierTo(
            x + wavelength * 3 / 4,
            y + amplitude,
            x + wavelength,
            y,
          );
        x += wavelength;
      }
      canvas.drawPath(path, paint);
    }
  }

  void _confetti(Canvas canvas, Size size) {
    final colours = [scheme.primary, scheme.tertiary, scheme.secondary];
    final alpha = _dark ? .26 : .20;
    _tiles(size, 128, 128, (o, _, _) {
      for (final piece in _confettiPieces) {
        final paint = Paint()
          ..color = colours[piece.colour].withValues(alpha: alpha);
        canvas
          ..save()
          ..translate(o.dx + piece.x, o.dy + piece.y)
          ..rotate(piece.angle);
        if (piece.round) {
          canvas.drawCircle(Offset.zero, 2.4, paint);
        } else {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(-4, -1.6, 8, 3.2),
              const Radius.circular(1.6),
            ),
            paint,
          );
        }
        canvas.restore();
      }
    });
  }

  void _gradient(Canvas canvas, Rect rect, int from, int to) {
    final shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [_tint(from), background, _tint(to)],
      stops: const [0, .5, 1],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(ChatPatternPainter oldDelegate) =>
      oldDelegate.patternId != patternId ||
      oldDelegate.scheme != scheme ||
      oldDelegate.background != background;
}

/// A heart [size] wide, centred on [c].
Path _heart(Offset c, double size) {
  Offset p(double x, double y) =>
      Offset(c.dx + (x - .5) * size, c.dy + (y - .45) * size);
  final a = p(.5, .9);
  final path = Path()..moveTo(a.dx, a.dy);
  void curve(List<double> v) {
    final p1 = p(v[0], v[1]), p2 = p(v[2], v[3]), p3 = p(v[4], v[5]);
    path.cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);
  }

  curve([.15, .65, 0, .45, 0, .3]);
  curve([0, .12, .14, 0, .28, 0]);
  curve([.39, 0, .47, .07, .5, .16]);
  curve([.53, .07, .61, 0, .72, 0]);
  curve([.86, 0, 1, .12, 1, .3]);
  curve([1, .45, .85, .65, .5, .9]);
  return path..close();
}

/// A five-pointed star with outer radius [r], centred on [c].
Path _star(Offset c, double r) {
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final radius = i.isEven ? r : r * .45;
    final angle = -math.pi / 2 + i * math.pi / 5;
    final point = c + Offset(math.cos(angle), math.sin(angle)) * radius;
    i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
  }
  return path..close();
}

/// A short wavy stroke [width] long, starting at [start].
Path _squiggle(Offset start, double width) {
  final step = width / 4;
  final path = Path()..moveTo(start.dx, start.dy);
  for (var i = 0; i < 4; i++) {
    final x = start.dx + i * step;
    path.quadraticBezierTo(
      x + step / 2,
      start.dy + (i.isEven ? -4 : 4),
      x + step,
      start.dy,
    );
  }
  return path;
}

typedef _Piece = ({double x, double y, double angle, int colour, bool round});

/// Fixed positions, so the confetti tiles identically on every frame.
final List<_Piece> _confettiPieces = () {
  final random = math.Random(7);
  return List<_Piece>.generate(
    14,
    (i) => (
      x: random.nextDouble() * 128,
      y: random.nextDouble() * 128,
      angle: random.nextDouble() * math.pi,
      colour: i % 3,
      round: random.nextInt(3) == 0,
    ),
  );
}();
