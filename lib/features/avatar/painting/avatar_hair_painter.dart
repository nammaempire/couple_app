import 'dart:math' as math;
import 'dart:ui';

import 'package:couple_app/features/avatar/painting/avatar_brush.dart';
import 'package:couple_app/features/avatar/painting/avatar_palette.dart';

/// Paints hair in two layers: [drawBack] goes behind the head and body (so
/// long hair falls behind the shoulders) and [drawFront] over the face.
///
/// Shapes are designed for the oval head; the caller stretches the canvas
/// to the chosen face shape. So every shape depends only on the style and
/// is built once: the boolean path operations behind curls and fringes are
/// far too slow to redo on every paint.
class AvatarHairPainter {
  AvatarHairPainter(this.b, this.style, this.p);

  final AvatarBrush b;
  final String style;
  final AvatarPalette p;

  Canvas get _c => b.canvas;

  // ---- Shared shapes ------------------------------------------------------

  /// Finished hair shapes in design space, by style and layer. Painting
  /// never mutates a path, so they're safe to share.
  static final _shapes = <String, Path>{};

  static Path _memo(String key, Path Function() build) =>
      _shapes.putIfAbsent(key, build);

  static Path _cap({double cy = 44, double rx = 23.4, double ry = 25.6}) =>
      AvatarBrush.ovalPath(50, cy, rx, ry);

  /// A hairline with a centre part, falling to [sideY] at the temples.
  static Path _partedHairline(double sideY, {double crown = 26}) =>
      AvatarBrush.above(
        Path()
          ..moveTo(0, sideY)
          ..lineTo(30.6, sideY)
          ..lineTo(30.8, 42)
          ..cubicTo(31.5, 33, 38, crown + 1.5, 46, crown)
          ..quadraticBezierTo(48.6, crown, 50, crown + 2.4)
          ..quadraticBezierTo(51.4, crown, 54, crown)
          ..cubicTo(62, crown + 1.5, 68.5, 33, 69.2, 42)
          ..lineTo(69.4, sideY)
          ..lineTo(100, sideY),
      );

  static Path _curlyFringe(double y) => AvatarBrush.union([
    Path()..addRect(Rect.fromLTRB(0, -40, 100, y - 2)),
    Path()..addRect(const Rect.fromLTRB(0, -40, 31.2, 51)),
    Path()..addRect(const Rect.fromLTRB(68.8, -40, 100, 51)),
    for (final (x, dy) in const [
      (34.6, 0.0),
      (40.8, 1.4),
      (47.2, 1.8),
      (53.6, 1.6),
      (60.0, 1.0),
      (65.8, 2.2),
    ])
      AvatarBrush.circlePath(x, y + dy, 3.9),
    AvatarBrush.circlePath(30.6, 50.4, 3.2),
    AvatarBrush.circlePath(69.4, 50.4, 3.2),
  ]);

  /// Circles of radius [r] along the upper part of an ellipse.
  static Path _bumps(
    double cx,
    double cy,
    double rx,
    double ry,
    double r, {
    double from = -15,
    double to = 195,
    int count = 11,
  }) {
    return AvatarBrush.union([
      for (var i = 0; i < count; i++)
        () {
          final t = (from + (to - from) * i / (count - 1)) * math.pi / 180;
          return AvatarBrush.circlePath(
            cx + rx * math.cos(t),
            cy - ry * math.sin(t),
            r,
          );
        }(),
    ]);
  }

  void _shine(Path path, {double width = 1.6}) =>
      b.stroke(path, p.hairLight.withValues(alpha: .9), width);

  void _strands(List<Path> paths, {double width = .8}) {
    if (!b.detailed) return;
    final paint = b.line(p.hairShade.withValues(alpha: .75), width);
    for (final path in paths) {
      _c.drawPath(path, paint);
    }
  }

  static Path _curve(
    double x1,
    double y1,
    double cx,
    double cy,
    double x2,
    double y2,
  ) => Path()
    ..moveTo(x1, y1)
    ..quadraticBezierTo(cx, cy, x2, y2);

  // ---- Back layer -----------------------------------------------------------

  void drawBack() {
    switch (style) {
      case 'curly':
        b.path(
          _memo(
            'back-curly',
            () => AvatarBrush.union([
              _cap(cy: 43, rx: 23.5, ry: 25),
              AvatarBrush.circlePath(27, 53, 5),
              AvatarBrush.circlePath(73, 53, 5),
            ]),
          ),
          p.hairShade,
        );
      case 'afro':
        b.path(_afro, p.hairShade);
      case 'bob':
        b.path(_bob, p.hairShade);
      case 'long':
        b.path(
          Path()
            ..moveTo(26, 46)
            ..cubicTo(24.6, 26, 36, 17.6, 50, 17.6)
            ..cubicTo(64, 17.6, 75.4, 26, 74, 46)
            ..cubicTo(74, 62, 77, 78, 78.5, 92)
            ..quadraticBezierTo(64, 96.5, 50, 95)
            ..quadraticBezierTo(36, 96.5, 21.5, 92)
            ..cubicTo(23, 78, 26, 62, 26, 46)
            ..close(),
          p.hairShade,
        );
      case 'wavy':
        final half = Path()
          ..moveTo(50, 17)
          ..cubicTo(36, 17, 24.2, 26, 25.6, 46)
          ..quadraticBezierTo(26, 54, 23.4, 61)
          ..quadraticBezierTo(20.6, 69, 23.4, 77)
          ..quadraticBezierTo(25.6, 84, 21, 92)
          ..quadraticBezierTo(36, 96.5, 50, 95)
          ..close();
        b.path(
          _memo(
            'back-wavy',
            () => AvatarBrush.union([half, AvatarBrush.mirrored(half)]),
          ),
          p.hairShade,
        );
      case 'ponytail':
        b.path(_cap(), p.hairShade);
        final tail = Path()
          ..moveTo(62, 22)
          ..cubicTo(77, 19, 84.5, 30, 82, 45)
          ..cubicTo(80.5, 56, 83, 64, 77.4, 73)
          ..quadraticBezierTo(75.6, 64, 74, 56)
          ..cubicTo(72.4, 44, 72.4, 34, 62, 30)
          ..close();
        b.path(tail, p.hair);
        _strands([
          _curve(74, 30, 79.5, 42, 77.5, 58),
          _curve(70, 28, 76, 40, 75.5, 54),
        ]);
        _c.save();
        _c.translate(71.6, 25.2);
        _c.rotate(.5);
        _c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: 3, height: 6.4),
            const Radius.circular(1.4),
          ),
          b.fill(const Color(0xFFE05C7B)),
        );
        _c.restore();
      case 'bun':
        b.path(_cap(), p.hairShade);
        b.circle(50, 13.6, 8.8, p.hair);
        _strands([
          _curve(44.5, 11, 49, 6.5, 55, 9.5),
          _curve(43.5, 16, 50, 21, 56.5, 15),
        ], width: .9);
        _shine(_curve(44, 10.5, 46, 7, 50, 6.2), width: 1.3);
      case 'braids':
      case 'short':
      case 'side':
      case 'quiff':
        b.path(_cap(), p.hairShade);
      default:
        break;
    }
  }

  static Path get _afro => _memo(
    'afro',
    () => AvatarBrush.union([
      AvatarBrush.ovalPath(50, 37, 29.5, 27),
      _bumps(50, 37, 28, 26, 6, from: -40, to: 220, count: 13),
    ]),
  );

  static Path get _bob => _memo('bob', () => _bobShape);

  static Path get _bobShape => Path()
    ..moveTo(24.6, 63)
    ..lineTo(24.4, 42)
    ..cubicTo(24.4, 26, 35, 17.5, 50, 17.5)
    ..cubicTo(65, 17.5, 75.6, 26, 75.6, 42)
    ..lineTo(75.4, 63)
    ..quadraticBezierTo(75.4, 67.6, 70, 67.2)
    ..lineTo(30, 67.2)
    ..quadraticBezierTo(24.6, 67.6, 24.6, 63)
    ..close();

  // ---- Front layer ----------------------------------------------------------

  void drawFront() {
    switch (style) {
      case 'short':
        _front(
          () => _cap(cy: 44, rx: 23.4, ry: 25.6),
          () => AvatarBrush.above(
            Path()
              ..moveTo(0, 50)
              ..lineTo(30.4, 50)
              ..lineTo(30.6, 41)
              ..cubicTo(31.5, 35, 35, 31.4, 40, 31)
              ..cubicTo(44, 30.6, 46, 33, 50, 32.2)
              ..cubicTo(55, 31.2, 58, 29.6, 62, 30.2)
              ..cubicTo(66.5, 31, 69, 35, 69.4, 41)
              ..lineTo(69.6, 50)
              ..lineTo(100, 50),
          ),
        );
        _strands([
          _curve(45, 20.5, 42, 25, 40.5, 30.8),
          _curve(56, 20, 54.5, 26, 51.5, 31.6),
        ]);
        _shine(_curve(34.5, 26, 38.5, 21.2, 45, 19.8));
      case 'buzz':
        b.path(
          _memo(
            'front-buzz',
            () => AvatarBrush.intersect(
              _cap(cy: 44.8, rx: 22, ry: 22.6),
              AvatarBrush.above(
                Path()
                  ..moveTo(0, 47)
                  ..lineTo(30.2, 47)
                  ..lineTo(30.4, 38)
                  ..cubicTo(32, 31.5, 38, 29.6, 50, 29.6)
                  ..cubicTo(62, 29.6, 68, 31.5, 69.6, 38)
                  ..lineTo(69.8, 47)
                  ..lineTo(100, 47),
              ),
            ),
          ),
          Color.lerp(p.hair, p.skin, .22)!,
        );
      case 'side':
        _front(
          () => AvatarBrush.union([
            _cap(cy: 44, rx: 23.6, ry: 25.8),
            AvatarBrush.ovalPath(56, 23.6, 15.6, 8.4),
          ]),
          () => AvatarBrush.above(
            Path()
              ..moveTo(0, 50)
              ..lineTo(30.4, 50)
              ..lineTo(30.6, 40)
              ..cubicTo(31, 33, 34, 29, 38.5, 27.4)
              ..cubicTo(44, 29, 52, 33.6, 60, 34.6)
              ..cubicTo(65, 35.2, 68.6, 37, 69.4, 42)
              ..lineTo(69.6, 50)
              ..lineTo(100, 50),
          ),
        );
        b.stroke(_curve(38.5, 27.6, 37.9, 22.6, 39.8, 19.6), p.hairShade, .9);
        _strands([
          _curve(43, 19, 52, 23, 60.5, 33),
          _curve(50, 16.4, 60, 21, 67, 34),
        ]);
        _shine(_curve(50, 17.6, 58, 15.6, 66, 19));
      case 'quiff':
        _front(
          () => AvatarBrush.union([
            _cap(cy: 45, rx: 22.8, ry: 24),
            Path()
              ..moveTo(30.5, 33)
              ..cubicTo(28.5, 17, 40, 8, 54, 9.5)
              ..cubicTo(66, 10.5, 73.5, 18, 70.5, 33)
              ..close(),
          ]),
          () => AvatarBrush.above(
            Path()
              ..moveTo(0, 46)
              ..lineTo(30, 46)
              ..lineTo(30.4, 37)
              ..cubicTo(31.5, 31, 36, 29.2, 42, 29.2)
              ..lineTo(58, 29.2)
              ..cubicTo(64, 29.2, 68.5, 31, 69.6, 37)
              ..lineTo(70, 46)
              ..lineTo(100, 46),
          ),
        );
        _strands([
          _curve(37, 28, 37, 17, 46, 12),
          _curve(46, 28.6, 47, 16, 57, 11.4),
          _curve(56, 28.6, 60, 18, 66, 15.6),
        ], width: .9);
        _shine(_curve(41, 15, 47, 10.8, 55, 10.8));
      case 'curly':
        _front(
          () => AvatarBrush.union([
            _cap(cy: 43, rx: 23.5, ry: 25),
            _bumps(50, 43, 23, 24.5, 5.5),
          ]),
          () => _curlyFringe(30),
        );
        _curls(const [
          (38, 22),
          (47, 18.5),
          (57, 20),
          (64.5, 26),
          (30.5, 32),
          (69.5, 38),
        ]);
      case 'afro':
        _front(() => _afro, () => _curlyFringe(29.4));
        _curls(const [
          (32, 18),
          (42, 12),
          (54, 10.5),
          (65, 14),
          (73, 24),
          (25, 30),
          (76, 38),
          (24.5, 42),
          (48, 21),
        ]);
      case 'bob':
        _front(
          () => _bob,
          () => AvatarBrush.above(
            Path()
              ..moveTo(0, 70)
              ..lineTo(30.6, 70)
              ..lineTo(30.8, 40)
              ..quadraticBezierTo(31.4, 34, 38, 34)
              ..lineTo(62, 34)
              ..quadraticBezierTo(68.6, 34, 69.2, 40)
              ..lineTo(69.4, 70)
              ..lineTo(100, 70),
          ),
        );
        _strands([
          for (final x in const [38.0, 44.0, 50.0, 56.0, 62.0])
            _curve(x - .6, 24, x - .2, 29, x, 33.6),
        ]);
        _shine(_curve(32.5, 30, 36, 22.6, 44, 20));
      case 'long':
        final strand = Path()
          ..moveTo(26.6, 40)
          ..cubicTo(25.4, 56, 23, 72, 22, 86)
          ..quadraticBezierTo(25.2, 89.6, 29.2, 87.4)
          ..cubicTo(30, 74, 31.4, 60, 31, 44)
          ..close();
        _front(() => _cap(cy: 44, rx: 23.5, ry: 26), () => _partedHairline(60));
        b.path(strand, p.hair);
        b.path(AvatarBrush.mirrored(strand), p.hair);
        _strands([
          _curve(27.6, 56, 26, 72, 25.4, 84),
          _curve(72.4, 56, 74, 72, 74.6, 84),
          _curve(44, 27, 36, 30, 32.5, 40),
          _curve(56, 27, 64, 30, 67.5, 40),
        ]);
        _shine(_curve(34, 25.6, 38.5, 21, 45, 19.6));
      case 'wavy':
        final strand = Path()
          ..moveTo(26.4, 40)
          ..quadraticBezierTo(23, 50, 26, 58)
          ..quadraticBezierTo(29, 66, 25, 74)
          ..quadraticBezierTo(21.6, 82, 25.2, 89)
          ..quadraticBezierTo(28.6, 90.6, 31, 87)
          ..quadraticBezierTo(28, 81, 31.4, 74)
          ..quadraticBezierTo(34.6, 66, 31.6, 58)
          ..quadraticBezierTo(29.6, 51, 31, 42)
          ..close();
        _front(
          () => AvatarBrush.union([
            _cap(cy: 43.6, rx: 24, ry: 26.5),
            AvatarBrush.ovalPath(44, 24, 16, 9),
          ]),
          () => AvatarBrush.above(
            Path()
              ..moveTo(0, 60)
              ..lineTo(30.6, 60)
              ..lineTo(30.8, 42)
              ..cubicTo(31.5, 36, 36, 32, 42, 31.6)
              ..cubicTo(50, 31, 56, 28, 60, 26.5)
              ..cubicTo(65, 29, 69, 34, 69.2, 42)
              ..lineTo(69.4, 60)
              ..lineTo(100, 60),
          ),
        );
        b.path(strand, p.hair);
        b.path(AvatarBrush.mirrored(strand), p.hair);
        b.stroke(_curve(60, 26.6, 59.6, 22, 57.6, 18.4), p.hairShade, .9);
        _strands([
          _curve(55, 22, 46, 24, 36, 33),
          _curve(28, 62, 30.5, 68, 27.5, 76),
          _curve(72, 62, 69.5, 68, 72.5, 76),
        ]);
        _shine(_curve(33.5, 26.6, 38.5, 20.6, 46, 18.6));
      case 'ponytail':
        _front(
          () => _cap(cy: 44, rx: 23.2, ry: 25.4),
          () => AvatarBrush.above(
            Path()
              ..moveTo(0, 49)
              ..lineTo(30.4, 49)
              ..lineTo(30.6, 40)
              ..cubicTo(31.5, 33, 37, 29.2, 44, 29.6)
              ..cubicTo(51, 30, 58, 33, 62.5, 33.8)
              ..cubicTo(66.5, 34.4, 69, 37, 69.4, 41)
              ..lineTo(69.6, 49)
              ..lineTo(100, 49),
          ),
        );
        _strands([
          _curve(37, 27, 48, 19, 66, 21),
          _curve(48, 30, 58, 24, 69, 27),
        ]);
        _shine(_curve(34, 26, 38.5, 21.4, 45, 20));
      case 'bun':
        _front(
          () => _cap(cy: 44, rx: 23, ry: 25.2),
          () => _partedHairline(48, crown: 29),
        );
        b.oval(50, 20.4, 5.6, 1.5, p.hairShade);
        _strands([
          _curve(44, 29.6, 43, 23, 46.5, 20.5),
          _curve(56, 29.6, 57, 23, 53.5, 20.5),
        ]);
        _shine(_curve(34.5, 27, 38.5, 22.6, 44.5, 21));
      case 'braids':
        _front(
          () => _cap(cy: 44, rx: 23.2, ry: 25.4),
          () => _partedHairline(49, crown: 28),
        );
        _braid(-1);
        _braid(1);
        _shine(_curve(34.5, 26.4, 38.5, 22, 44.5, 20.4));
      case 'bald':
        b.stroke(
          _curve(36, 29, 39.5, 25.4, 45, 24.4),
          const Color(0x40FFFFFF),
          2,
        );
      default:
        break;
    }
  }

  /// Fills the part of [outer] inside [region] (the hair over the face),
  /// built once per style.
  void _front(Path Function() outer, Path Function() region) => b.path(
    _memo('front-$style', () => AvatarBrush.intersect(outer(), region())),
    p.hair,
  );

  void _curls(List<(double, double)> spots) {
    if (!b.detailed) return;
    final paint = b.line(p.hairShade.withValues(alpha: .8), .7);
    for (final (x, y) in spots) {
      _c.drawArc(
        Rect.fromCircle(center: Offset(x, y), radius: 1.8),
        .4,
        3.6,
        false,
        paint,
      );
    }
  }

  void _braid(double side) {
    final x = 50 + side * 23.4;
    for (var i = 0; i < 8; i++) {
      final y = 51.5 + i * 5;
      final dx = (i.isEven ? -.5 : .5) * side;
      final w = 3.4 - i * .1;
      final link = AvatarBrush.ovalPath(x + dx, y, w, 3.1);
      b.path(link, i.isEven ? p.hair : AvatarBrush.shade(p.hair, .08));
      if (b.detailed) {
        b.stroke(
          _curve(
            x + dx - w * .7,
            y + .6,
            x + dx,
            y + 2.2,
            x + dx + w * .7,
            y + .6,
          ),
          p.hairShade,
          .6,
        );
      }
    }
    _c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, 90.6), width: 4.4, height: 1.8),
        const Radius.circular(.9),
      ),
      b.fill(const Color(0xFFE05C7B)),
    );
    b.path(
      Path()
        ..moveTo(x - 2, 91.2)
        ..quadraticBezierTo(x, 96.5, x + 2, 91.2)
        ..close(),
      p.hair,
    );
  }
}
