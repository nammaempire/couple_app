import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/avatar/painting/avatar_brush.dart';
import 'package:couple_app/features/avatar/painting/avatar_face_shape.dart';
import 'package:couple_app/features/avatar/painting/avatar_palette.dart';

enum _Eye {
  open,
  glossy,
  teary,
  wide,
  lookDown,
  happyClosed,
  restClosed,
  heart,
}

/// Paints the neck, ears, head and everything on the face: eyes, brows,
/// nose, mouth, cheeks, facial hair and expression extras (tears, a kiss
/// heart, sleepy z's).
class AvatarFacePainter {
  AvatarFacePainter(this.b, this.config, this.p, this.expression)
    : shape = AvatarFaceShape.of(config.face);

  final AvatarBrush b;
  final AvatarConfig config;
  final AvatarPalette p;
  final AvatarExpression expression;
  final AvatarFaceShape shape;

  Canvas get _c => b.canvas;

  static const _eyeY = 47.6;
  static const _leftEyeX = 41.0;
  static const _rightEyeX = 59.0;
  static const _mouthY = 60.0;

  // ---- Neck, ears, head -------------------------------------------------

  void drawNeck() {
    final neck = RRect.fromLTRBR(
      43.4,
      shape.chin - 12,
      56.6,
      88,
      const Radius.circular(3),
    );
    _c.drawRRect(neck, b.fill(p.skin));
    _c.save();
    _c.clipRRect(neck);
    b.path(shape.path.shift(const Offset(0, 3.4)), p.skinShade);
    _c.restore();
  }

  void drawEars() {
    for (final side in const [-1.0, 1.0]) {
      final x = 50 + side * (shape.halfWidth - .4);
      b.oval(x, 48.6, 3.7, 4.9, p.skin);
      b.oval(x + side * .7, 48.8, 1.9, 3.1, p.skinShade);
    }
  }

  void drawHead() {
    b.path(shape.path, p.skin);
    if (config.hair == 'bald') return;
    // A soft shade under the hairline gives the face some depth.
    _c.save();
    _c.clipPath(shape.path);
    b.oval(
      50,
      shape.top - 6,
      shape.halfWidth + 4,
      15,
      p.skinShade.withValues(alpha: .35),
    );
    _c.restore();
  }

  // ---- Cheeks -------------------------------------------------------------

  double get _blushStrength => switch (expression) {
    AvatarExpression.blush => .9,
    AvatarExpression.kiss => .7,
    AvatarExpression.love => .62,
    AvatarExpression.pout => .5,
    AvatarExpression.laugh || AvatarExpression.happy => .45,
    AvatarExpression.wink => .45,
    AvatarExpression.crying => .42,
    AvatarExpression.sad => .22,
    _ => .32,
  };

  void drawCheeks() {
    final strength = math.min(1.0, _blushStrength * (p.darkSkin ? 1.35 : 1));
    final big = expression == AvatarExpression.blush;
    for (final side in const [-1.0, 1.0]) {
      final center = Offset(50 + side * 12.6, 55.6);
      final r = big ? 5.6 : 4.4;
      final paint = Paint()
        ..shader = Gradient.radial(center, r, [
          AvatarPalette.blush.withValues(alpha: strength * .75),
          AvatarPalette.blush.withValues(alpha: 0),
        ]);
      _c.drawCircle(center, r, paint);
    }
    if (big && b.detailed) {
      final lines = b.line(
        AvatarBrush.shade(AvatarPalette.blush, .25).withValues(alpha: .7),
        .6,
      );
      for (final side in const [-1.0, 1.0]) {
        for (var i = 0; i < 3; i++) {
          final x = 50 + side * (10.8 + i * 1.6);
          _c.drawLine(Offset(x + .7, 54.6), Offset(x - .7, 56.8), lines);
        }
      }
    }
  }

  // ---- Facial hair --------------------------------------------------------

  Path get _jawArea {
    final grown = shape.path.transform(
      Float64List.fromList([
        1.05, 0, 0, 0, //
        0, 1.04, 0, 0,
        0, 0, 1, 0,
        -2.5, -1.8, 0, 1,
      ]),
    );
    final w = shape.halfWidth;
    final below = Path()
      ..moveTo(0, 46)
      ..lineTo(50 - w + 2.2, 46)
      ..cubicTo(50 - w + 3.2, 53, 35, 59, 39.6, 58.6)
      ..cubicTo(43, 58.2, 45, 55.8, 50, 55.6)
      ..cubicTo(55, 55.8, 57, 58.2, 60.4, 58.6)
      ..cubicTo(65, 59, 50 + w - 3.2, 53, 50 + w - 2.2, 46)
      ..lineTo(100, 46)
      ..lineTo(100, 100)
      ..lineTo(0, 100)
      ..close();
    return AvatarBrush.intersect(grown, below);
  }

  /// Beard, stubble and goatee sit under the mouth.
  void drawFacialHair() {
    switch (config.facialHair) {
      case 'stubble':
        b.path(_jawArea, Color.lerp(p.skin, p.hair, p.darkSkin ? .4 : .3)!);
      case 'beard':
        final beard = AvatarBrush.subtract(
          _jawArea,
          AvatarBrush.ovalPath(50, 60.6, 5.4, 2.7),
        );
        b.path(beard, p.hair);
        if (b.detailed) {
          final strands = b.line(p.hairShade.withValues(alpha: .6), .55);
          for (final x in const [36.0, 40.5, 59.5, 64.0]) {
            _c.drawLine(
              Offset(x, 61),
              Offset(x + (x < 50 ? 1 : -1), 64.5),
              strands,
            );
          }
        }
      case 'goatee':
        final c = shape.chin;
        final goatee = Path()
          ..moveTo(45, 63.6)
          ..quadraticBezierTo(50, 62.2, 55, 63.6)
          ..quadraticBezierTo(56, c - 1, 50, c + 1.4)
          ..quadraticBezierTo(44, c - 1, 45, 63.6)
          ..close();
        b.path(goatee, p.hair);
    }
  }

  /// Moustaches sit over the top lip, so they are drawn after the mouth.
  void drawMoustache() {
    if (!const {'moustache', 'beard', 'goatee'}.contains(config.facialHair)) {
      return;
    }
    final m = Path()
      ..moveTo(50, 56.3)
      ..cubicTo(47, 55.1, 42.8, 55.6, 41.6, 59.4)
      ..cubicTo(44.4, 57.9, 47.4, 58.5, 50, 57.6)
      ..cubicTo(52.6, 58.5, 55.6, 57.9, 58.4, 59.4)
      ..cubicTo(57.2, 55.6, 53, 55.1, 50, 56.3)
      ..close();
    b.path(m, p.hair);
  }

  // ---- Nose ----------------------------------------------------------------

  void drawNose() {
    final nose = Path()
      ..moveTo(48.2, 54.2)
      ..quadraticBezierTo(50, 56.2, 51.8, 54.2);
    b.stroke(nose, p.skinDeep, 1.3);
  }

  // ---- Mouth ---------------------------------------------------------------

  void drawMouth() {
    const y = _mouthY;
    switch (expression) {
      case AvatarExpression.neutral:
        b.stroke(
          Path()
            ..moveTo(46.6, y - .2)
            ..quadraticBezierTo(50, y + 1.9, 53.4, y - .2),
          p.ink,
          1.3,
        );
      case AvatarExpression.happy:
      case AvatarExpression.love:
        _openSmile(width: 5.6, depth: 4.8);
      case AvatarExpression.wink:
        _openSmile(width: 5.2, depth: 4.4, tilt: -.9);
      case AvatarExpression.laugh:
        _openSmile(width: 6.6, depth: 6.4, teeth: 1.8, tongue: true);
      case AvatarExpression.blush:
        b.stroke(
          Path()
            ..moveTo(47.6, y + .2)
            ..quadraticBezierTo(50, y + 1.9, 52.4, y + .2),
          p.ink,
          1.2,
        );
      case AvatarExpression.sad:
        b.stroke(
          Path()
            ..moveTo(46.2, y + 1.8)
            ..quadraticBezierTo(50, y - 1.4, 53.8, y + 1.8),
          p.ink,
          1.35,
        );
      case AvatarExpression.crying:
        final wail = Path()
          ..moveTo(45, y + 2.6)
          ..quadraticBezierTo(50, y - 3.4, 55, y + 2.6)
          ..quadraticBezierTo(50, y + 5, 45, y + 2.6)
          ..close();
        _filledMouth(wail, tongueAt: Offset(50, y + 3.4), tongueRx: 3);
      case AvatarExpression.sleepy:
        b.oval(50, y + .6, 1.4, 1.6, AvatarPalette.mouth);
      case AvatarExpression.surprised:
        _filledMouth(
          AvatarBrush.ovalPath(50, y + 1, 2.7, 3.3),
          tongueAt: Offset(50, y + 3.4),
          tongueRx: 2,
        );
      case AvatarExpression.kiss:
        _puckeredLips();
      case AvatarExpression.pout:
        _poutyLips();
    }
  }

  void _openSmile({
    required double width,
    required double depth,
    double tilt = 0,
    double teeth = 1.5,
    bool tongue = true,
  }) {
    const y = _mouthY - 1;
    final l = Offset(50 - width, y + tilt);
    final r = Offset(50 + width, y - tilt);
    final smile = Path()
      ..moveTo(l.dx, l.dy)
      ..quadraticBezierTo(50, y + 1.1, r.dx, r.dy)
      ..cubicTo(r.dx - .6, y + depth, l.dx + .6, y + depth, l.dx, l.dy)
      ..close();
    _filledMouth(
      smile,
      teethHeight: teeth,
      tongueAt: tongue ? Offset(50, y + depth * .9) : null,
      tongueRx: width * .55,
    );
  }

  void _filledMouth(
    Path mouth, {
    double teethHeight = 0,
    Offset? tongueAt,
    double tongueRx = 3,
  }) {
    b.path(mouth, AvatarPalette.mouth);
    _c.save();
    _c.clipPath(mouth);
    final bounds = mouth.getBounds();
    if (teethHeight > 0 && b.detailed) {
      _c.drawRect(
        Rect.fromLTWH(
          bounds.left,
          bounds.top - 1,
          bounds.width,
          teethHeight + 1.2,
        ),
        b.fill(AvatarPalette.teeth),
      );
    }
    if (tongueAt != null) {
      b.oval(tongueAt.dx, tongueAt.dy, tongueRx, 2.2, AvatarPalette.tongue);
    }
    _c.restore();
  }

  void _puckeredLips() {
    const x = 50.6;
    const y = _mouthY + .4;
    final lips = Path()
      ..moveTo(x, y - 2.6)
      ..cubicTo(x + 2.9, y - 3.2, x + 3.3, y - .2, x + 1.2, y)
      ..cubicTo(x + 3.3, y + .2, x + 2.9, y + 3.4, x, y + 2.8)
      ..cubicTo(x - 2.9, y + 3.4, x - 3.3, y + .2, x - 1.2, y)
      ..cubicTo(x - 3.3, y - .2, x - 2.9, y - 3.2, x, y - 2.6)
      ..close();
    b.path(lips, p.lip);
    b.stroke(
      Path()
        ..moveTo(x - 1.6, y)
        ..lineTo(x + 1.6, y),
      AvatarBrush.shade(p.lip, .4),
      .7,
    );
  }

  void _poutyLips() {
    const y = _mouthY + .6;
    final lips = Path()
      ..moveTo(46.2, y + .6)
      ..cubicTo(47, y - 2.6, 49, y - 2.4, 50, y - 1.6)
      ..cubicTo(51, y - 2.4, 53, y - 2.6, 53.8, y + .6)
      ..cubicTo(53, y + 3.4, 47, y + 3.4, 46.2, y + .6)
      ..close();
    b.path(lips, p.lip);
    b.stroke(
      Path()
        ..moveTo(46.6, y + .7)
        ..quadraticBezierTo(50, y - .4, 53.4, y + .7),
      AvatarBrush.shade(p.lip, .45),
      .75,
    );
    if (b.detailed) {
      b.oval(50.6, y + 1.7, 1.2, .5, const Color(0x66FFFFFF));
    }
  }

  // ---- Eyes ----------------------------------------------------------------

  (_Eye, _Eye) get _eyes => switch (expression) {
    AvatarExpression.laugh => (_Eye.happyClosed, _Eye.happyClosed),
    AvatarExpression.love => (_Eye.heart, _Eye.heart),
    AvatarExpression.kiss => (_Eye.restClosed, _Eye.restClosed),
    AvatarExpression.wink => (_Eye.open, _Eye.happyClosed),
    AvatarExpression.blush => (_Eye.lookDown, _Eye.lookDown),
    AvatarExpression.sad => (_Eye.glossy, _Eye.glossy),
    AvatarExpression.crying => (_Eye.teary, _Eye.teary),
    AvatarExpression.sleepy => (_Eye.restClosed, _Eye.restClosed),
    AvatarExpression.surprised => (_Eye.wide, _Eye.wide),
    _ => (_Eye.open, _Eye.open),
  };

  void drawEyes() {
    final (left, right) = _eyes;
    _eye(_leftEyeX, -1, left);
    _eye(_rightEyeX, 1, right);
  }

  void _eye(double cx, double side, _Eye kind) {
    const cy = _eyeY;
    switch (kind) {
      case _Eye.open:
        _openEye(cx, cy, side);
      case _Eye.glossy:
        _openEye(cx, cy, side, glossy: true);
      case _Eye.teary:
        _openEye(cx, cy, side, glossy: true);
        b.stroke(
          Path()
            ..moveTo(cx - 3, cy + 3.2)
            ..quadraticBezierTo(cx, cy + 4.6, cx + 3, cy + 3.2),
          AvatarPalette.tear,
          1.3,
        );
      case _Eye.wide:
        b.oval(cx, cy, 4, 4.6, const Color(0xFFFFFFFF));
        _c.drawOval(AvatarBrush.ovalRect(cx, cy, 4, 4.6), b.line(p.ink, .7));
        b.circle(cx, cy + .2, 2.3, p.iris);
        b.circle(cx, cy + .2, 1.3, p.pupil);
        b.circle(cx + .8, cy - .7, .75, const Color(0xFFFFFFFF));
      case _Eye.lookDown:
        _c.save();
        _c.clipRect(Rect.fromLTRB(cx - 6, cy - .2, cx + 6, cy + 6));
        _openEye(cx, cy + .6, side, lids: false);
        _c.restore();
        b.stroke(
          Path()
            ..moveTo(cx - 3.6, cy + .2)
            ..quadraticBezierTo(cx, cy - 1.3, cx + 3.6, cy + .2),
          p.ink,
          1.25,
        );
        _lashes(cx, cy + .2, side, down: true);
      case _Eye.happyClosed:
        b.stroke(
          Path()
            ..moveTo(cx - 3.5, cy + 1.3)
            ..quadraticBezierTo(cx, cy - 3.4, cx + 3.5, cy + 1.3),
          p.ink,
          1.6,
        );
        if (config.eyes == 'lashes') _flick(cx + side * 3.5, cy + 1.3, side);
      case _Eye.restClosed:
        b.stroke(
          Path()
            ..moveTo(cx - 3.4, cy - .2)
            ..quadraticBezierTo(cx, cy + 3, cx + 3.4, cy - .2),
          p.ink,
          1.5,
        );
        if (config.eyes == 'lashes' || config.eyes == 'almond') {
          _lashes(cx, cy + .6, side, down: true);
        }
      case _Eye.heart:
        b.path(AvatarBrush.heart(cx, cy, 8.6), AvatarPalette.heart);
        b.oval(cx - 1.9, cy - 1.7, 1.1, .8, const Color(0xB3FFFFFF));
    }
  }

  void _openEye(
    double cx,
    double cy,
    double side, {
    bool glossy = false,
    bool lids = true,
  }) {
    final style = config.eyes;
    if (style == 'almond') {
      final almond = Path()
        ..moveTo(cx - 4.3 * side, cy + .5)
        ..quadraticBezierTo(cx, cy - 4.6, cx + 4.3 * side, cy - .9)
        ..quadraticBezierTo(cx + .4 * side, cy + 4, cx - 4.3 * side, cy + .5)
        ..close();
      b.path(almond, const Color(0xFFFFFCFA));
      _c.save();
      _c.clipPath(almond);
      _iris(cx, cy - .1, 2.8, 2.8, glossy);
      _c.restore();
      if (lids) {
        b.stroke(
          Path()
            ..moveTo(cx - 4.3 * side, cy + .5)
            ..quadraticBezierTo(cx, cy - 4.6, cx + 4.3 * side, cy - .9)
            ..lineTo(cx + 5.4 * side, cy - 1.9),
          p.ink,
          1.25,
        );
      }
      return;
    }

    if (style == 'smiley') {
      _c.save();
      _c.clipPath(
        AvatarBrush.subtract(
          AvatarBrush.ovalPath(cx, cy, 5, 5),
          AvatarBrush.circlePath(cx, cy + 5.6, 4.3),
        ),
      );
      _iris(cx, cy, 3, 3.5, glossy);
      _c.restore();
      return;
    }

    _iris(cx, cy, 2.9, 3.5, glossy);
    if (style == 'lashes' && lids) _lashes(cx, cy - .4, side);
  }

  void _iris(double cx, double cy, double rx, double ry, bool glossy) {
    b.oval(cx, cy, rx, ry, p.iris);
    b.oval(cx, cy + .35, rx * .6, ry * .62, p.pupil);
    const white = Color(0xFFFFFFFF);
    b.circle(cx + rx * .36, cy - ry * .36, glossy ? 1.35 : 1.05, white);
    b.circle(
      cx - rx * .34,
      cy + ry * .4,
      glossy ? .75 : .5,
      white.withValues(alpha: .85),
    );
  }

  /// Three lashes on the outer upper edge of an eye.
  void _lashes(double cx, double cy, double side, {bool down = false}) {
    final paint = b.line(p.ink, .9);
    final dir = down ? 1.0 : -1.0;
    for (var i = 0; i < 3; i++) {
      final a = (.25 + i * .3) * math.pi / 2;
      final start = Offset(
        cx + side * 3 * math.cos(a * .9),
        cy + dir * 3.2 * math.sin(a * .55),
      );
      final end = start + Offset(side * 1.5, dir * (1 + i * .3));
      _c.drawLine(start, end, paint);
    }
  }

  void _flick(double x, double y, double side) => _c.drawLine(
    Offset(x, y),
    Offset(x + side * 1.4, y - 1.2),
    b.line(p.ink, 1),
  );

  // ---- Brows ---------------------------------------------------------------

  void drawBrows() {
    final (inner, outer, lift) = switch (expression) {
      AvatarExpression.happy || AvatarExpression.love => (-.4, -.2, -.6),
      AvatarExpression.laugh => (-.8, 0.0, -1.4),
      AvatarExpression.kiss => (-.6, 0.0, -.4),
      AvatarExpression.wink => (0.0, 0.0, -.6),
      AvatarExpression.blush => (-1.4, .4, -.2),
      AvatarExpression.sad => (-2.6, .9, 0.0),
      AvatarExpression.crying => (-2.9, 1.1, 0.0),
      AvatarExpression.sleepy => (.6, .6, .6),
      AvatarExpression.surprised => (-.6, -.2, -3.4),
      AvatarExpression.pout => (2.4, -.6, 0.0),
      AvatarExpression.neutral => (0.0, 0.0, 0.0),
    };
    for (final side in const [-1.0, 1.0]) {
      final winkDrop = expression == AvatarExpression.wink && side > 0
          ? 1.1
          : 0.0;
      _brow(side, inner + lift + winkDrop, outer + lift + winkDrop);
    }
  }

  void _brow(double side, double innerDy, double outerDy) {
    final (thickIn, thickOut, arch, peak) = switch (config.brows) {
      'thick' => (3.0, 2.0, 1.3, .5),
      'arched' => (1.9, 1.0, 3.0, .62),
      'straight' => (2.2, 1.8, .3, .5),
      _ => (2.0, 1.2, 1.7, .5),
    };
    const baseY = 40.4;
    final pi = Offset(50 + side * 4.6, baseY + innerDy);
    final po = Offset(50 + side * 13.8, baseY + .3 + outerDy);
    final ctrl = Offset(
      pi.dx + (po.dx - pi.dx) * peak,
      (pi.dy + po.dy) / 2 - arch,
    );
    final mid = (thickIn + thickOut) / 4;
    final brow = Path()
      ..moveTo(pi.dx, pi.dy - thickIn / 2)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy - mid, po.dx, po.dy - thickOut / 2)
      ..arcToPoint(
        Offset(po.dx, po.dy + thickOut / 2),
        radius: Radius.circular(thickOut / 2),
        clockwise: side > 0,
      )
      ..quadraticBezierTo(ctrl.dx, ctrl.dy + mid, pi.dx, pi.dy + thickIn / 2)
      ..arcToPoint(
        Offset(pi.dx, pi.dy - thickIn / 2),
        radius: Radius.circular(thickIn / 2),
        clockwise: side > 0,
      )
      ..close();
    b.path(brow, p.brow);
  }

  // ---- Expression extras ---------------------------------------------------

  void drawExtras() {
    switch (expression) {
      case AvatarExpression.crying:
        final stream = Path()
          ..moveTo(38.4, 50.6)
          ..cubicTo(37, 55, 37.6, 60, 36.2, 65.4)
          ..quadraticBezierTo(38.2, 68, 40.2, 65.4)
          ..cubicTo(39.4, 60, 40.4, 55, 41.2, 50.6)
          ..close();
        for (final path in [stream, AvatarBrush.mirrored(stream)]) {
          b.path(path, AvatarPalette.tear.withValues(alpha: .92));
        }
        if (b.detailed) {
          final shine = b.line(const Color(0xB3FFFFFF), .5);
          _c.drawLine(const Offset(39, 54), const Offset(38.4, 60), shine);
          _c.drawLine(const Offset(61.6, 54), const Offset(61.0, 60), shine);
        }
      case AvatarExpression.kiss:
        b.path(AvatarBrush.heart(60.2, 56.4, 5.4), AvatarPalette.heart);
        b.oval(59.1, 55.2, .7, .5, const Color(0xB3FFFFFF));
      case AvatarExpression.sleepy:
        _z(72.5, 27.5, 4.2);
        _z(79, 18.5, 5.6);
      default:
        break;
    }
  }

  void _z(double x, double y, double s) {
    final z = Path()
      ..moveTo(x, y)
      ..lineTo(x + s, y)
      ..lineTo(x, y + s)
      ..lineTo(x + s, y + s);
    b.stroke(z, const Color(0xFFFFFFFF), s * .42);
    b.stroke(z, const Color(0xFF5B6CD6), s * .22);
  }
}
