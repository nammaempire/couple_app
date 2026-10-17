import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:couple_app/features/stickers/models/sticker_scene.dart';

/// Paints a sticker's [StickerProp]s over its art area.
///
/// A sticker paints twice: once behind the avatars ([front] false: big
/// heart, sun, moon, clouds, trails) and once in front of them (small
/// hearts, sparkles, flowers, mugs...). Positions are fractions of the art
/// size, nudged around the avatars' [heads].
class StickerPropsPainter extends CustomPainter {
  const StickerPropsPainter({
    required this.props,
    required this.front,
    required this.layout,
    required this.heads,
    required this.accent,
    required this.dark,
  });

  final List<StickerProp> props;
  final bool front;
  final StickerLayout layout;

  /// Centres of the drawn heads, sender first, in art coordinates.
  final List<Offset> heads;
  final Color accent;
  final bool dark;

  static const _gold = Color(0xFFFFC23D);
  static const _confettiColors = [
    Color(0xFFFF6F91),
    Color(0xFFFFC23D),
    Color(0xFF4CC9A6),
    Color(0xFF6C8CFF),
    Color(0xFFB57BFF),
    Color(0xFFFF9F5A),
  ];

  static bool isBackProp(StickerProp prop) => switch (prop) {
    StickerProp.bigHeart ||
    StickerProp.sun ||
    StickerProp.moonStars ||
    StickerProp.rainCloud ||
    StickerProp.heartTrail => true,
    _ => false,
  };

  @override
  void paint(Canvas canvas, Size size) {
    for (final prop in props) {
      if (prop == StickerProp.confetti) {
        // Confetti is split between the layers so it surrounds the couple.
        _confetti(canvas, size, front: front);
        continue;
      }
      if (isBackProp(prop) == front) continue;
      switch (prop) {
        case StickerProp.floatingHearts:
          _floatingHearts(canvas, size);
        case StickerProp.bigHeart:
          _bigHeart(canvas, size);
        case StickerProp.brokenHeart:
          _brokenHeart(canvas, size);
        case StickerProp.rainCloud:
          _rainCloud(canvas, size);
        case StickerProp.sun:
          _sun(canvas, size);
        case StickerProp.moonStars:
          _moonStars(canvas, size);
        case StickerProp.sparkles:
          _sparkles(canvas, size);
        case StickerProp.flowers:
          _flowers(canvas, size);
        case StickerProp.coffee:
          _coffee(canvas, size);
        case StickerProp.zzz:
          _zzz(canvas, size);
        case StickerProp.musicNotes:
          _musicNotes(canvas, size);
        case StickerProp.plasterHeart:
          _plasterHeart(canvas, size);
        case StickerProp.heartTrail:
          _heartTrail(canvas, size);
        case StickerProp.confetti:
          break;
      }
    }
  }

  // ---- Shapes -------------------------------------------------------------

  /// A heart [width] wide, centred on [c].
  static Path heartPath(Offset c, double width) {
    final w = width;
    final h = width * .9;
    final x = c.dx - w / 2;
    final y = c.dy - h / 2;
    Offset p(double fx, double fy) => Offset(x + w * fx, y + h * fy);
    final a = p(.5, .28);
    return Path()
      ..moveTo(a.dx, a.dy)
      ..cubicTo(
        p(.5, .22).dx,
        p(.5, .22).dy,
        p(.42, 0).dx,
        p(.42, 0).dy,
        p(.25, 0).dx,
        p(.25, 0).dy,
      )
      ..cubicTo(
        p(.06, 0).dx,
        p(.06, 0).dy,
        p(0, .18).dx,
        p(0, .18).dy,
        p(0, .34).dx,
        p(0, .34).dy,
      )
      ..cubicTo(
        p(0, .62).dx,
        p(0, .62).dy,
        p(.28, .8).dx,
        p(.28, .8).dy,
        p(.5, 1).dx,
        p(.5, 1).dy,
      )
      ..cubicTo(
        p(.72, .8).dx,
        p(.72, .8).dy,
        p(1, .62).dx,
        p(1, .62).dy,
        p(1, .34).dx,
        p(1, .34).dy,
      )
      ..cubicTo(
        p(1, .18).dx,
        p(1, .18).dy,
        p(.94, 0).dx,
        p(.94, 0).dy,
        p(.75, 0).dx,
        p(.75, 0).dy,
      )
      ..cubicTo(
        p(.58, 0).dx,
        p(.58, 0).dy,
        p(.5, .22).dx,
        p(.5, .22).dy,
        a.dx,
        a.dy,
      )
      ..close();
  }

  void _heart(
    Canvas canvas,
    Offset c,
    double width, {
    Color? color,
    double angle = 0,
    bool shine = true,
  }) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final path = heartPath(Offset.zero, width);
    canvas.drawPath(path, Paint()..color = color ?? accent);
    if (shine) {
      // A small highlight makes flat hearts look glossy.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(-width * .22, -width * .2),
          width: width * .2,
          height: width * .12,
        ),
        Paint()..color = Colors.white.withValues(alpha: .55),
      );
    }
    canvas.restore();
  }

  /// A four-pointed twinkle.
  void _twinkle(Canvas canvas, Offset c, double r, Color color) {
    final i = r * .22;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + i, c.dy - i, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + i, c.dy + i, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - i, c.dy + i, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - i, c.dy - i, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  Color get _soft => Color.lerp(accent, Colors.white, .45)!;

  /// Whether a sun or moon fills the top-right corner, so small props
  /// should stay out of it.
  bool get _skyTaken =>
      props.contains(StickerProp.sun) || props.contains(StickerProp.moonStars);

  /// [fx], [fy] (fractions of the art) are inside the sun/moon corner.
  bool _inSky(double fx, double fy) => _skyTaken && fx > .66 && fy < .42;

  // ---- Props --------------------------------------------------------------

  void _floatingHearts(Canvas canvas, Size s) {
    final w = s.width;
    final spots = layout == StickerLayout.solo
        ? const [
            (.12, .22, .085, -.35),
            (.88, .16, .1, .3),
            (.84, .5, .06, .15),
            (.15, .55, .055, -.2),
            (.72, .06, .05, .1),
          ]
        : const [
            (.1, .22, .08, -.35),
            (.9, .16, .095, .3),
            (.52, .07, .065, 0.0),
            (.86, .5, .055, .2),
            (.15, .56, .05, -.2),
          ];
    for (final (i, (fx, fy, fs, angle)) in spots.indexed) {
      if (_inSky(fx, fy)) continue;
      _heart(
        canvas,
        Offset(w * fx, s.height * fy),
        w * fs,
        color: i.isEven ? accent : _soft,
        angle: angle,
      );
    }
  }

  void _bigHeart(Canvas canvas, Size s) {
    final w = s.width;
    final c = Offset(
      w * .5,
      s.height * (layout == StickerLayout.solo ? .4 : .42),
    );
    final width = w * (layout == StickerLayout.solo ? .78 : .7);
    final path = heartPath(c, width);
    canvas.drawPath(
      path,
      Paint()
        ..color = dark
            ? accent.withValues(alpha: .32)
            : Color.lerp(accent, Colors.white, .62)!,
    );
    // A soft inner glow ring.
    canvas.drawPath(
      heartPath(c.translate(0, -width * .03), width * .82),
      Paint()
        ..color = Colors.white.withValues(alpha: dark ? .06 : .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * .02,
    );
  }

  void _brokenHeart(Canvas canvas, Size s) {
    final w = s.width;
    final Offset c;
    final double width;
    if (layout == StickerLayout.apart && heads.length > 1) {
      c = Offset(w * .5, (heads[0].dy + heads[1].dy) / 2);
      width = w * .2;
    } else if (layout == StickerLayout.solo) {
      c = Offset(w * .84, s.height * .26);
      width = w * .18;
    } else {
      c = Offset(w * .5, s.height * .14);
      width = w * .18;
    }
    final heart = heartPath(Offset.zero, width);
    // Zigzag crack down the middle.
    final h = width * .9;
    final crack = <Offset>[
      Offset(0, -h * .24),
      Offset(-width * .08, -h * .05),
      Offset(width * .06, h * .1),
      Offset(-width * .05, h * .26),
      Offset(0, h * .5),
    ];
    Path half(bool left) {
      final p = Path()..moveTo(crack.first.dx, crack.first.dy - h);
      for (final point in crack) {
        p.lineTo(point.dx, point.dy);
      }
      p
        ..lineTo(0, h)
        ..lineTo(left ? -width : width, h)
        ..lineTo(left ? -width : width, -h)
        ..close();
      return Path.combine(PathOperation.intersect, heart, p);
    }

    for (final left in [true, false]) {
      canvas.save();
      canvas.translate(c.dx + (left ? -1 : 1) * width * .06, c.dy);
      canvas.rotate(left ? -.16 : .16);
      canvas.drawPath(half(left), Paint()..color = accent);
      canvas.restore();
    }
  }

  void _cloud(Canvas canvas, Offset c, double width, Color color) {
    final r = width / 4;
    final paint = Paint()..color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: c.translate(0, r * .45),
          width: width,
          height: r * 1.3,
        ),
        Radius.circular(r * .65),
      ),
      paint,
    );
    canvas.drawCircle(c.translate(-r * .9, r * .1), r * .85, paint);
    canvas.drawCircle(c.translate(r * .15, -r * .35), r * 1.15, paint);
    canvas.drawCircle(c.translate(r * 1.1, r * .15), r * .75, paint);
  }

  void _rainCloud(Canvas canvas, Size s) {
    final w = s.width;
    final head = heads.isEmpty ? Offset(w * .5, s.height * .5) : heads.first;
    final width = w * .3;
    final Offset c;
    if (layout == StickerLayout.solo) {
      // Beside the head, raining past the cheek.
      c = Offset(w * .19, w * .12);
    } else if (layout == StickerLayout.apart) {
      c = Offset(
        head.dx.clamp(w * .2, w * .8).toDouble(),
        math.max(w * .1, head.dy - w * .28),
      );
    } else {
      c = Offset(w * .5, w * .1);
    }

    final drop = Paint()..color = const Color(0xFF7FB2F0);
    for (final (fx, fy) in const [
      (-.28, .55),
      (-.06, .78),
      (.18, .6),
      (.34, .86),
      (-.18, 1.0),
    ]) {
      final p = c.translate(width * fx, width * fy * .5 + width * .12);
      final r = width * .035;
      final path = Path()
        ..moveTo(p.dx, p.dy - r * 2.4)
        ..quadraticBezierTo(p.dx + r * 1.1, p.dy - r * .3, p.dx, p.dy + r)
        ..quadraticBezierTo(p.dx - r * 1.1, p.dy - r * .3, p.dx, p.dy - r * 2.4)
        ..close();
      canvas.drawPath(path, drop);
    }
    _cloud(
      canvas,
      c,
      width,
      dark ? const Color(0xFF8E97AD) : const Color(0xFFB9C3D6),
    );
    _cloud(
      canvas,
      c.translate(-width * .04, -width * .04),
      width * .92,
      dark ? const Color(0xFFA9B1C4) : const Color(0xFFDDE3EE),
    );
  }

  void _sun(Canvas canvas, Size s) {
    final w = s.width;
    final c = Offset(w * .84, s.height * .2);
    final r = w * .085;
    final rays = Paint()
      ..color = const Color(0xFFFFB938)
      ..strokeWidth = r * .22
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 10; i++) {
      final a = i * math.pi / 5 + .15;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * r * 1.35, c + dir * r * 1.75, rays);
    }
    canvas.drawCircle(c, r * 1.12, Paint()..color = const Color(0x55FFD66B));
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFFFC93F));
    canvas.drawCircle(
      c.translate(-r * .3, -r * .3),
      r * .3,
      Paint()..color = Colors.white.withValues(alpha: .45),
    );
  }

  void _moonStars(Canvas canvas, Size s) {
    final w = s.width;
    final c = Offset(w * .85, s.height * .19);
    final r = w * .075;
    final moon = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: c, radius: r)),
      Path()..addOval(
        Rect.fromCircle(
          center: c.translate(-r * .55, -r * .35),
          radius: r * .9,
        ),
      ),
    );
    canvas.drawCircle(
      c,
      r * 1.5,
      Paint()
        ..color = dark
            ? const Color(0xFFFFE08A).withValues(alpha: .16)
            : Colors.white.withValues(alpha: .45),
    );
    canvas.drawPath(moon, Paint()..color = const Color(0xFFFFD86B));

    final star = dark ? const Color(0xFFFFF1B8) : const Color(0xFFFFC23D);
    final zzz = props.contains(StickerProp.zzz);
    for (final (fx, fy, fr) in const [
      (.1, .12, .03),
      (.26, .05, .018),
      (.62, .08, .022),
      (.7, .3, .016),
      (.07, .4, .018),
      (.95, .4, .02),
    ]) {
      // Leave the left side to the Zs.
      if (zzz && fx < .3) continue;
      _twinkle(canvas, Offset(w * fx, s.height * fy), w * fr, star);
    }
  }

  void _sparkles(Canvas canvas, Size s) {
    final w = s.width;
    final white = dark ? Colors.white : Colors.white.withValues(alpha: .95);
    for (final (i, (fx, fy, fr)) in const [
      (.22, .07, .045),
      (.95, .34, .036),
      (.04, .4, .03),
      (.76, .06, .03),
      (.36, .2, .02),
      (.62, .16, .022),
    ].indexed) {
      if (_inSky(fx, fy)) continue;
      final c = Offset(w * fx, s.height * fy);
      _twinkle(canvas, c, w * fr, i.isEven ? _gold : white);
      if (i.isEven) _twinkle(canvas, c, w * fr * .4, Colors.white);
    }
  }

  void _flower(Canvas canvas, Offset c, double r, Color petal) {
    final paint = Paint()..color = petal;
    for (var i = 0; i < 5; i++) {
      final a = i * 2 * math.pi / 5 - math.pi / 2;
      canvas.drawCircle(
        c + Offset(math.cos(a), math.sin(a)) * r * .62,
        r * .5,
        paint,
      );
    }
    canvas.drawCircle(c, r * .38, Paint()..color = const Color(0xFFFFD34E));
  }

  void _leaf(Canvas canvas, Offset c, double len, double angle) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(len * .5, -len * .35, len, 0)
      ..quadraticBezierTo(len * .5, len * .35, 0, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF6DBE7A));
    canvas.restore();
  }

  void _flowers(Canvas canvas, Size s) {
    final w = s.width;
    final y = s.height - w * .1;
    void bunch(double x, bool flip) {
      final d = flip ? -1.0 : 1.0;
      _leaf(canvas, Offset(x, y + w * .02), w * .09, flip ? -2.5 : -.6);
      _leaf(canvas, Offset(x, y + w * .02), w * .08, flip ? -.3 : -2.9);
      _flower(
        canvas,
        Offset(x - d * w * .045, y - w * .02),
        w * .05,
        const Color(0xFFFF8FAB),
      );
      _flower(
        canvas,
        Offset(x + d * w * .04, y - w * .05),
        w * .045,
        const Color(0xFFFFB5C8),
      );
      _flower(
        canvas,
        Offset(x + d * w * .005, y + w * .03),
        w * .04,
        const Color(0xFFC49BFF),
      );
    }

    if (layout != StickerLayout.solo) bunch(w * .1, false);
    bunch(w * .88, true);
  }

  void _mug(Canvas canvas, Offset c, double size, Color color) {
    final body = RRect.fromRectAndCorners(
      Rect.fromCenter(center: c, width: size, height: size * 1.05),
      topLeft: Radius.circular(size * .08),
      topRight: Radius.circular(size * .08),
      bottomLeft: Radius.circular(size * .28),
      bottomRight: Radius.circular(size * .28),
    );
    canvas.drawCircle(
      c.translate(size * .5, 0),
      size * .24,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * .12,
    );
    canvas.drawRRect(body, Paint()..color = color);
    // A little heart on the mug.
    _heart(
      canvas,
      c.translate(0, size * .06),
      size * .36,
      color: Colors.white,
      shine: false,
    );
    // Steam.
    final steam = Paint()
      ..color = (dark ? Colors.white : const Color(0xFF9A8790)).withValues(
        alpha: .7,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * .07
      ..strokeCap = StrokeCap.round;
    for (final dx in [-size * .2, size * .14]) {
      final top = c.translate(dx, -size * .62);
      final path = Path()
        ..moveTo(top.dx, top.dy)
        ..cubicTo(
          top.dx - size * .14,
          top.dy - size * .16,
          top.dx + size * .14,
          top.dy - size * .3,
          top.dx,
          top.dy - size * .46,
        );
      canvas.drawPath(path, steam);
    }
  }

  void _coffee(Canvas canvas, Size s) {
    final w = s.width;
    final y = s.height - w * .11;
    if (layout != StickerLayout.solo) {
      _mug(canvas, Offset(w * .1, y), w * .12, const Color(0xFFF0806F));
    }
    _mug(canvas, Offset(w * .86, y), w * .12, const Color(0xFF7FA7E8));
  }

  void _zzz(Canvas canvas, Size s) {
    final w = s.width;
    // Where the Zs start and which way they drift.
    final Offset start;
    final double drift;
    if (layout == StickerLayout.solo || heads.isEmpty) {
      start = Offset(w * .22, s.height * .52);
      drift = -.6;
    } else if (_skyTaken) {
      // The moon has the top right: float off the left of the sender.
      final head = heads.first;
      start = Offset(math.max(head.dx - w * .19, w * .22), head.dy - w * .02);
      drift = -.65;
    } else {
      final head = heads.last;
      start = Offset(
        math.min(head.dx + w * .14, w * .8),
        math.max(head.dy - w * .16, w * .22),
      );
      drift = 1;
    }
    final color = dark ? const Color(0xFFD9D3FF) : const Color(0xFF7466C8);
    for (final (i, scale) in const [.028, .036, .046].indexed) {
      final a = w * scale;
      final c = start.translate(drift * i * w * .07, -i * w * .08);
      final z = Path()
        ..moveTo(c.dx - a, c.dy - a)
        ..lineTo(c.dx + a, c.dy - a)
        ..lineTo(c.dx - a, c.dy + a)
        ..lineTo(c.dx + a, c.dy + a);
      canvas.drawPath(
        z,
        Paint()
          ..color = color.withValues(alpha: .6 + i * .2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = a * .42
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  void _note(
    Canvas canvas,
    Offset c,
    double size,
    Color color, {
    bool pair = false,
  }) {
    final paint = Paint()..color = color;
    final stem = Paint()
      ..color = color
      ..strokeWidth = size * .12
      ..strokeCap = StrokeCap.round;
    void head(Offset at) {
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(-.45);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: size * .5,
          height: size * .36,
        ),
        paint,
      );
      canvas.restore();
    }

    final top = c.translate(size * .2, -size);
    head(c);
    canvas.drawLine(c.translate(size * .2, 0), top, stem);
    if (pair) {
      final c2 = c.translate(size * .55, -size * .15);
      head(c2);
      canvas.drawLine(
        c2.translate(size * .2, 0),
        top.translate(size * .55, -size * .15),
        stem,
      );
      canvas.drawLine(
        top,
        top.translate(size * .55, -size * .15),
        stem..strokeWidth = size * .2,
      );
    } else {
      final flag = Path()
        ..moveTo(top.dx, top.dy)
        ..quadraticBezierTo(
          top.dx + size * .45,
          top.dy + size * .2,
          top.dx + size * .3,
          top.dy + size * .55,
        );
      canvas.drawPath(
        flag,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = size * .12
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _musicNotes(Canvas canvas, Size s) {
    final w = s.width;
    final purple = dark ? const Color(0xFFC9B6FF) : const Color(0xFF8A6BE0);
    _note(canvas, Offset(w * .3, s.height * .2), w * .09, purple, pair: true);
    _note(canvas, Offset(w * .7, s.height * .14), w * .08, accent);
    _note(canvas, Offset(w * .05, s.height * .44), w * .065, accent);
    _note(canvas, Offset(w * .95, s.height * .38), w * .06, purple);
  }

  void _confetti(Canvas canvas, Size s, {required bool front}) {
    final w = s.width;
    const pieces = [
      (.06, .1, 0.4),
      (.18, .06, 1.2),
      (.3, .16, 2.1),
      (.42, .04, .3),
      (.56, .12, 1.7),
      (.68, .05, .9),
      (.8, .14, 2.4),
      (.94, .08, 1.1),
      (.04, .34, 1.9),
      (.95, .32, .6),
      (.12, .55, 2.7),
      (.9, .6, 1.4),
      (.24, .3, .8),
      (.76, .32, 2.2),
      (.5, .24, 1.5),
      (.03, .74, .2),
      (.97, .8, 1.8),
      (.36, .02, 2.9),
    ];
    for (final (i, (fx, fy, angle)) in pieces.indexed) {
      // Back layer: the outer pieces; front: a few near the faces.
      final isFront = i % 3 == 0;
      if (isFront != front) continue;
      final color = _confettiColors[i % _confettiColors.length];
      final c = Offset(w * fx, s.height * fy);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(angle);
      final paint = Paint()..color = color;
      switch (i % 3) {
        case 0:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset.zero,
                width: w * .05,
                height: w * .022,
              ),
              Radius.circular(w * .006),
            ),
            paint,
          );
        case 1:
          canvas.drawCircle(Offset.zero, w * .014, paint);
        default:
          final path = Path()
            ..moveTo(-w * .025, 0)
            ..quadraticBezierTo(-w * .012, -w * .018, 0, 0)
            ..quadraticBezierTo(w * .012, w * .018, w * .025, 0);
          canvas.drawPath(
            path,
            paint
              ..style = PaintingStyle.stroke
              ..strokeWidth = w * .01
              ..strokeCap = StrokeCap.round,
          );
      }
      canvas.restore();
    }
  }

  void _plaster(Canvas canvas, Offset c, double len, double angle) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: len,
      height: len * .32,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(len * .16)),
      Paint()..color = const Color(0xFFF6D3A8),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: len * .34,
          height: len * .26,
        ),
        Radius.circular(len * .05),
      ),
      Paint()..color = const Color(0xFFE9B887),
    );
    final dot = Paint()..color = const Color(0xFFD9A06E);
    for (final dx in [-.34, -.27, .27, .34]) {
      for (final dy in [-.05, .05]) {
        canvas.drawCircle(Offset(len * dx, len * dy), len * .018, dot);
      }
    }
    canvas.restore();
  }

  void _plasterHeart(Canvas canvas, Size s) {
    final w = s.width;
    final solo = layout == StickerLayout.solo;
    final c = solo
        ? Offset(w * .82, s.height * .24)
        : Offset(w * .5, s.height * .16);
    final width = w * (solo ? .2 : .22);
    _heart(canvas, c, width);
    _plaster(canvas, c.translate(0, width * .02), width * .78, -.6);
    _plaster(canvas, c.translate(0, width * .02), width * .78, .6);
  }

  void _heartTrail(Canvas canvas, Size s) {
    if (heads.length < 2) return;
    final w = s.width;
    final a = heads[0].translate(w * .13, -w * .06);
    final b = heads[1].translate(-w * .13, -w * .06);
    final control = Offset((a.dx + b.dx) / 2, math.min(a.dy, b.dy) - w * .26);
    final dot = Paint()
      ..color = dark
          ? Colors.white.withValues(alpha: .55)
          : accent.withValues(alpha: .55);
    const count = 13;
    for (var i = 0; i <= count; i++) {
      final t = i / count;
      if ((t - .5).abs() < .12) continue; // leave room for the heart
      final p = Offset(
        (1 - t) * (1 - t) * a.dx + 2 * (1 - t) * t * control.dx + t * t * b.dx,
        (1 - t) * (1 - t) * a.dy + 2 * (1 - t) * t * control.dy + t * t * b.dy,
      );
      canvas.drawCircle(p, w * .009, dot);
    }
    final apex = Offset(
      .25 * a.dx + .5 * control.dx + .25 * b.dx,
      .25 * a.dy + .5 * control.dy + .25 * b.dy,
    );
    _heart(canvas, apex, w * .13);
  }

  @override
  bool shouldRepaint(StickerPropsPainter old) =>
      old.front != front ||
      old.layout != layout ||
      old.accent != accent ||
      old.dark != dark ||
      !_sameList(old.props, props) ||
      !_sameList(old.heads, heads);

  static bool _sameList<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
