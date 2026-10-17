import 'dart:ui';

import 'package:couple_app/features/avatar/painting/avatar_brush.dart';
import 'package:couple_app/features/avatar/painting/avatar_palette.dart';

/// Paints the shoulders and outfit. [drawBack] adds anything behind the
/// neck (a hoodie's hood); [drawFront] the torso and its details.
class AvatarOutfitPainter {
  AvatarOutfitPainter(this.b, this.outfit, this.p);

  final AvatarBrush b;
  final String outfit;
  final AvatarPalette p;

  Canvas get _c => b.canvas;

  static Path get _torso => Path()
    ..moveTo(4, 116)
    ..lineTo(6.5, 96)
    ..cubicTo(8.5, 86, 15, 80.6, 27, 78.2)
    ..lineTo(43, 74.6)
    ..lineTo(57, 74.6)
    ..lineTo(73, 78.2)
    ..cubicTo(85, 80.6, 91.5, 86, 93.5, 96)
    ..lineTo(96, 116)
    ..close();

  static Path _scoop(double depth, {double half = 7.4}) => Path()
    ..moveTo(50 - half, 74.4)
    ..cubicTo(
      50 - half + 1.2,
      74.4 + depth,
      50 + half - 1.2,
      74.4 + depth,
      50 + half,
      74.4,
    );

  void drawBack() {
    if (outfit != 'hoodie') return;
    b.path(
      Path()
        ..moveTo(30, 80)
        ..cubicTo(30, 70.5, 39.5, 67.6, 50, 67.6)
        ..cubicTo(60.5, 67.6, 70, 70.5, 70, 80)
        ..close(),
      p.outfitDeep,
    );
  }

  void drawFront() {
    switch (outfit) {
      case 'hoodie':
        _hoodie();
      case 'shirt':
        _shirt();
      case 'kurta':
        _kurta();
      case 'saree':
        _saree();
      case 'dress':
        _dress();
      case 'sweater':
        _sweater();
      default:
        _tee();
    }
  }

  void _body(Color color) {
    b.path(_torso, color);
    if (!b.detailed) return;
    // Soft folds where the arms meet the body.
    final fold = b.line(AvatarBrush.shade(color, .12), .9);
    _c.drawPath(
      Path()
        ..moveTo(20.5, 81)
        ..quadraticBezierTo(18.6, 88, 19.6, 100),
      fold,
    );
    _c.drawPath(
      Path()
        ..moveTo(79.5, 81)
        ..quadraticBezierTo(81.4, 88, 80.4, 100),
      fold,
    );
  }

  void _neckOpening(Path edge) {
    final open = Path.from(edge)..close();
    b.path(open, p.skin);
    // Shadow the neck just inside the collar.
    _c.save();
    _c.clipPath(open);
    b.path(edge.shift(const Offset(0, -2.2))..close(), p.skinShade);
    _c.restore();
  }

  void _tee() {
    _body(p.outfit);
    final edge = _scoop(7.4);
    _neckOpening(edge);
    b.stroke(edge, p.outfitShade, 1.8);
  }

  void _hoodie() {
    _body(p.outfit);
    final v = Path()
      ..moveTo(42.4, 74.4)
      ..lineTo(50, 85)
      ..lineTo(57.6, 74.4);
    _neckOpening(v);
    final rimL = Path()
      ..moveTo(39.6, 74.2)
      ..quadraticBezierTo(42, 81, 51.4, 86.6);
    final rimR = Path()
      ..moveTo(60.4, 74.2)
      ..quadraticBezierTo(58, 81, 48.6, 86.6);
    for (final rim in [rimL, rimR]) {
      b.stroke(rim, p.outfitShade, 3.6);
      b.stroke(rim, p.outfit, 2.2);
    }
    final string = p.outfit.computeLuminance() > .6
        ? const Color(0xFFB9B2AD)
        : const Color(0xFFF7F3EF);
    for (final (top, bottom) in const [
      (Offset(45.6, 81.4), Offset(44.6, 94)),
      (Offset(54.4, 81.4), Offset(55.4, 94)),
    ]) {
      _c.drawLine(top, bottom, b.line(string, 1.1));
      b.oval(bottom.dx, bottom.dy + 1.2, .8, 1.5, p.outfitDeep);
    }
  }

  void _shirt() {
    _body(p.outfit);
    _neckOpening(
      Path()
        ..moveTo(43.6, 74.4)
        ..lineTo(50, 83)
        ..lineTo(56.4, 74.4),
    );
    final collar = Path()
      ..moveTo(42.4, 73.4)
      ..lineTo(50, 82.8)
      ..lineTo(40.6, 81.8)
      ..lineTo(38.6, 77)
      ..close();
    for (final side in [collar, AvatarBrush.mirrored(collar)]) {
      b.path(side, p.outfitLight);
      b.stroke(side, p.outfitShade, .8);
    }
    b.stroke(
      Path()
        ..moveTo(50, 83)
        ..lineTo(50, 114),
      p.outfitShade,
      .9,
    );
    if (b.detailed) {
      for (final y in const [88.0, 95.0, 102.0]) {
        b.circle(51.6, y, .9, p.outfitLight);
      }
      _c.drawRRect(
        RRect.fromLTRBR(32, 88, 39.5, 96, const Radius.circular(1)),
        b.line(p.outfitShade, .7),
      );
    }
  }

  void _kurta() {
    _body(p.outfit);
    final edge = _scoop(4.4, half: 6.6);
    _neckOpening(edge);
    b.stroke(edge, p.outfitShade, 2.6);
    b.stroke(edge, p.trim, .7);
    b.path(
      Path()..addRect(const Rect.fromLTRB(48.5, 78.2, 51.5, 98)),
      p.outfitShade,
    );
    b.stroke(
      Path()
        ..moveTo(48.5, 78.2)
        ..lineTo(48.5, 98)
        ..lineTo(51.5, 98)
        ..lineTo(51.5, 78.2),
      p.trim,
      .6,
    );
    for (final y in const [82.0, 87.0, 92.0]) {
      b.circle(50, y, .85, p.trim);
    }
  }

  void _saree() {
    _body(p.outfitDeep);
    final edge = _scoop(6.8);
    _neckOpening(edge);
    b.stroke(edge, AvatarBrush.shade(p.outfitDeep, .15), 1.2);
    final drape = Path()
      ..moveTo(57.6, 74.8)
      ..lineTo(73, 78.2)
      ..cubicTo(85, 80.6, 91.5, 86, 93.5, 96)
      ..lineTo(95, 114)
      ..lineTo(32, 114)
      ..close();
    b.path(drape, p.outfit);
    if (b.detailed) {
      final pleat = b.line(p.outfitShade, .8);
      for (final d in const [8.0, 16.0, 24.0]) {
        _c.drawLine(Offset(60 + d * .55, 77), Offset(36 + d, 114), pleat);
      }
    }
    b.stroke(
      Path()
        ..moveTo(34.4, 114)
        ..lineTo(58.8, 75.6),
      p.trim,
      2.4,
    );
    if (b.detailed) {
      for (var i = 0; i < 5; i++) {
        final t = i / 4;
        b.circle(
          37.4 + (58 - 37.4) * t + 1.2,
          104.5 + (77.4 - 104.5) * t + .4,
          .5,
          AvatarBrush.shade(p.trim, .3),
        );
      }
    }
  }

  void _dress() {
    b.path(_torso, p.skin);
    if (b.detailed) {
      final bone = b.line(p.skinShade, .9);
      _c.drawPath(
        Path()
          ..moveTo(44.6, 80.6)
          ..quadraticBezierTo(40, 79.4, 36, 80.4),
        bone,
      );
      _c.drawPath(
        Path()
          ..moveTo(55.4, 80.6)
          ..quadraticBezierTo(60, 79.4, 64, 80.4),
        bone,
      );
    }
    final dress = Path()
      ..moveTo(15, 114)
      ..cubicTo(17.5, 96, 21, 90, 26, 86.8)
      ..quadraticBezierTo(33, 83.4, 40, 86)
      ..quadraticBezierTo(46, 88.2, 50, 91.6)
      ..quadraticBezierTo(54, 88.2, 60, 86)
      ..quadraticBezierTo(67, 83.4, 74, 86.8)
      ..cubicTo(79, 90, 82.5, 96, 85, 114)
      ..close();
    b.path(dress, p.outfit);
    b.stroke(
      Path()
        ..moveTo(26, 86.8)
        ..quadraticBezierTo(33, 83.4, 40, 86)
        ..quadraticBezierTo(46, 88.2, 50, 91.6)
        ..quadraticBezierTo(54, 88.2, 60, 86)
        ..quadraticBezierTo(67, 83.4, 74, 86.8),
      p.outfitShade,
      1,
    );
    for (final (bottom, top) in const [
      (Offset(32.4, 85), Offset(31.6, 77.6)),
      (Offset(67.6, 85), Offset(68.4, 77.6)),
    ]) {
      _c.drawLine(bottom, top, b.line(p.outfit, 2.2));
    }
  }

  void _sweater() {
    _body(p.outfit);
    if (b.detailed) {
      final cable = b.line(p.outfitShade.withValues(alpha: .7), .8);
      for (final x in const [31.0, 39.0, 61.0, 69.0]) {
        final wave = Path()..moveTo(x, 86);
        for (var y = 86.0; y < 114; y += 4) {
          wave.quadraticBezierTo(x + 1.4, y + 2, x, y + 4);
        }
        _c.drawPath(wave, cable);
      }
    }
    final edge = _scoop(5.8, half: 7);
    _neckOpening(edge);
    b.stroke(edge, p.outfitShade, 3.8);
    if (b.detailed) {
      final rib = b.line(p.outfitDeep.withValues(alpha: .8), .55);
      for (var i = 1; i < 10; i++) {
        final t = i / 10;
        final metric = edge.computeMetrics().first;
        final tangent = metric.getTangentForOffset(metric.length * t)!;
        final n = Offset(-tangent.vector.dy, tangent.vector.dx);
        _c.drawLine(
          tangent.position - n * 1.5,
          tangent.position + n * 1.5,
          rib,
        );
      }
    }
  }
}
