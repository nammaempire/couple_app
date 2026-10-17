import 'dart:typed_data';
import 'dart:ui';

import 'package:couple_app/features/avatar/painting/avatar_brush.dart';
import 'package:couple_app/features/avatar/painting/avatar_face_shape.dart';
import 'package:couple_app/features/avatar/painting/avatar_palette.dart';

/// Paints glasses and accessories (jewellery, hair pieces, hats, head
/// coverings and headphones) over the finished face and hair.
class AvatarAccessoryPainter {
  AvatarAccessoryPainter(this.b, this.p, {required this.earX});

  final AvatarBrush b;
  final AvatarPalette p;

  /// Left ear's x; the right ear mirrors it.
  final double earX;

  Canvas get _c => b.canvas;

  static const _hats = {'cap', 'beanie'};

  /// Whether [accessory] covers the top of the head, so hair above its
  /// brim is hidden.
  static bool coversHair(String accessory) => _hats.contains(accessory);

  /// Whether [accessory] wraps all the hair away (turban, headscarf), so no
  /// hair is drawn at all.
  static bool hidesAllHair(String accessory) =>
      accessory == 'turban' || accessory == 'headscarf';

  /// The region a hat hides, in oval-head units.
  static Path hatMask(String accessory) => Path()
    ..addRect(
      accessory == 'beanie'
          ? const Rect.fromLTRB(25, -40, 75, 33)
          : const Rect.fromLTRB(26.4, -40, 73.6, 32),
    );

  static final _hairClips = <String, Path>{};

  /// Where hair may still show under [accessory]'s hat, in oval-head units.
  /// Built once per hat: path operations are too slow for every paint.
  static Path hairClip(String accessory) => _hairClips.putIfAbsent(
    accessory,
    () => AvatarBrush.subtract(
      Path()..addRect(const Rect.fromLTRB(-20, -60, 120, 140)),
      hatMask(accessory),
    ),
  );

  // ---- Glasses --------------------------------------------------------------

  void drawGlasses(String style) {
    if (style == 'none') return;
    const frame = AvatarPalette.metal;
    final lenses = [
      for (final cx in const [41.0, 59.0])
        switch (style) {
          'round' => AvatarBrush.circlePath(cx, 47.6, 6),
          'sun' =>
            Path()..addRRect(
              RRect.fromRectAndCorners(
                Rect.fromCenter(
                  center: Offset(cx, 47.8),
                  width: 13.2,
                  height: 10.4,
                ),
                topLeft: const Radius.circular(2.4),
                topRight: const Radius.circular(2.4),
                bottomLeft: const Radius.circular(5.2),
                bottomRight: const Radius.circular(5.2),
              ),
            ),
          _ =>
            Path()..addRRect(
              RRect.fromRectAndRadius(
                Rect.fromCenter(
                  center: Offset(cx, 47.6),
                  width: 13,
                  height: 10.2,
                ),
                const Radius.circular(2.6),
              ),
            ),
        },
    ];

    // Arms back to the ears.
    final arm = b.line(frame, 1.1);
    _c.drawLine(const Offset(34.6, 46.6), Offset(earX + 1.5, 45.8), arm);
    _c.drawLine(const Offset(65.4, 46.6), Offset(100 - earX - 1.5, 45.8), arm);

    for (final lens in lenses) {
      if (style == 'sun') {
        final bounds = lens.getBounds();
        _c.drawPath(
          lens,
          Paint()
            ..shader = Gradient.linear(bounds.topCenter, bounds.bottomCenter, [
              const Color(0xFF242233),
              const Color(0xFF4A4562),
            ]),
        );
        b.stroke(
          Path()
            ..moveTo(bounds.left + 2.6, bounds.top + 2.2)
            ..lineTo(bounds.left + 5.4, bounds.top + 2.2),
          const Color(0x80FFFFFF),
          1,
        );
      } else {
        b.path(lens, const Color(0x1FFFFFFF));
      }
      b.stroke(lens, frame, style == 'sun' ? 1.3 : 1.2);
    }
    b.stroke(
      Path()
        ..moveTo(47, 46.6)
        ..quadraticBezierTo(50, 44.8, 53, 46.6),
      frame,
      1.2,
    );
  }

  // ---- Accessories ------------------------------------------------------------

  /// Bindi and earrings sit on the face, so they're drawn before the hair.
  /// A [bindi] goes with any [accessory].
  void drawOnFace(String accessory, {bool bindi = false}) {
    if (bindi) b.circle(50, 41.2, 1.25, const Color(0xFFD62C4A));
    switch (accessory) {
      case 'earrings':
        for (final x in [earX, 100 - earX]) {
          b.stroke(
            Path()..addOval(AvatarBrush.ovalRect(x, 55.4, 1.7, 1.9)),
            AvatarPalette.gold,
            .9,
          );
          b.circle(x, 57.4, .9, const Color(0xFFFFF4E0));
        }
    }
  }

  /// Everything that sits on or over the hair. Drawn in oval-head units.
  void drawOnHair(String accessory, Color hatColor) {
    switch (accessory) {
      case 'flower':
        _flower(67.4, 27.4);
      case 'bow':
        _bow(63.4, 21.6);
      case 'cap':
        _cap(hatColor);
      case 'beanie':
        _beanie(hatColor);
      case 'headphones':
        _headphones(hatColor);
      case 'turban':
        _turban(hatColor);
    }
  }

  void _flower(double x, double y) {
    const petal = Color(0xFFFF8FB1);
    _c.save();
    _c.translate(x, y);
    for (var i = 0; i < 5; i++) {
      _c.save();
      _c.rotate(i * 2 * 3.14159 / 5);
      _c.drawOval(
        Rect.fromCenter(center: const Offset(0, -2.6), width: 3.4, height: 4),
        b.fill(petal),
      );
      _c.restore();
    }
    _c.drawCircle(Offset.zero, 1.5, b.fill(const Color(0xFFFFD25A)));
    _c.restore();
    // A leaf tucked behind.
    b.path(
      Path()
        ..moveTo(x - 3.2, y + 2.4)
        ..quadraticBezierTo(x - 7, y + 3.4, x - 8, y + 6.4)
        ..quadraticBezierTo(x - 4.4, y + 6.6, x - 3.2, y + 2.4)
        ..close(),
      const Color(0xFF6DB37E),
    );
  }

  void _bow(double x, double y) {
    const red = Color(0xFFE8506E);
    final loop = Path()
      ..moveTo(x, y)
      ..cubicTo(x - 3, y - 5, x - 8, y - 3.6, x - 7.4, y + .4)
      ..cubicTo(x - 7, y + 4, x - 3, y + 3.6, x, y)
      ..close();
    b.path(loop, red);
    b.path(
      loop.transform(
        Float64List.fromList([
          -1, 0, 0, 0, //
          0, 1, 0, 0,
          0, 0, 1, 0,
          2 * x, 0, 0, 1,
        ]),
      ),
      red,
    );
    b.circle(x, y, 1.8, AvatarBrush.shade(red, .15));
    if (b.detailed) {
      b.stroke(
        Path()
          ..moveTo(x - 2.6, y - 1.2)
          ..quadraticBezierTo(x - 4.6, y - 2.2, x - 5.6, y - .8),
        AvatarBrush.shade(red, .25),
        .6,
      );
    }
  }

  void _cap(Color color) {
    final shade = AvatarBrush.shade(color, .18);
    final dome = Path()
      ..moveTo(26.2, 34)
      ..cubicTo(26.2, 20, 37, 14.4, 50, 14.4)
      ..cubicTo(63, 14.4, 73.8, 20, 73.8, 34)
      ..quadraticBezierTo(50, 29.6, 26.2, 34)
      ..close();
    b.path(dome, color);
    if (b.detailed) {
      final seam = b.line(shade, .7);
      _c.drawPath(
        Path()
          ..moveTo(50, 15)
          ..lineTo(50, 31),
        seam,
      );
      _c.drawPath(
        Path()
          ..moveTo(49, 15)
          ..quadraticBezierTo(38, 18, 35, 31.5),
        seam,
      );
      _c.drawPath(
        Path()
          ..moveTo(51, 15)
          ..quadraticBezierTo(62, 18, 65, 31.5),
        seam,
      );
    }
    b.circle(50, 14.8, 1.4, shade);
    final brim = Path()
      ..moveTo(25.4, 34.4)
      ..quadraticBezierTo(50, 28.6, 74.6, 34.4)
      ..quadraticBezierTo(76.6, 38.6, 71.6, 39)
      ..quadraticBezierTo(50, 35.2, 28.4, 39)
      ..quadraticBezierTo(23.4, 38.6, 25.4, 34.4)
      ..close();
    b.path(brim, shade);
  }

  void _beanie(Color color) {
    final shade = AvatarBrush.shade(color, .16);
    final deep = AvatarBrush.shade(color, .3);
    b.circle(50, 10.6, 4.6, AvatarBrush.tint(color, .35));
    final dome = Path()
      ..moveTo(26, 32)
      ..cubicTo(26, 18, 37, 11.8, 50, 11.8)
      ..cubicTo(63, 11.8, 74, 18, 74, 32)
      ..close();
    b.path(dome, color);
    if (b.detailed) {
      final knit = b.line(shade, .6);
      for (final x in const [36.0, 43.0, 50.0, 57.0, 64.0]) {
        _c.drawLine(Offset(x, 16 + (x - 50).abs() * .2), Offset(x, 28), knit);
      }
    }
    final cuff = RRect.fromLTRBR(
      24.8,
      27.4,
      75.2,
      36,
      const Radius.circular(3),
    );
    _c.drawRRect(cuff, b.fill(shade));
    if (b.detailed) {
      final rib = b.line(deep, .6);
      for (var x = 27.5; x < 74; x += 2.6) {
        _c.drawLine(Offset(x, 29), Offset(x, 34.4), rib);
      }
    }
  }

  void _headphones(Color accent) {
    const band = AvatarPalette.metal;
    final arc = Path()
      ..moveTo(24.6, 46)
      ..cubicTo(23.6, 22, 36, 14.4, 50, 14.4)
      ..cubicTo(64, 14.4, 76.4, 22, 75.4, 46);
    b.stroke(arc, band, 3.4);
    if (b.detailed) {
      b.stroke(
        Path()
          ..moveTo(36, 18.4)
          ..quadraticBezierTo(43, 15.4, 50, 15.2),
        const Color(0x40FFFFFF),
        .8,
      );
    }
    for (final side in const [-1.0, 1.0]) {
      final x = 50 + side * 24.6;
      _c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x - side * 1.6, 48.4),
            width: 4.4,
            height: 11.4,
          ),
          const Radius.circular(2.2),
        ),
        b.fill(band),
      );
      _c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x + side * 1.6, 48.4),
            width: 5,
            height: 13.4,
          ),
          const Radius.circular(2.5),
        ),
        b.fill(accent),
      );
    }
  }

  /// A wrapped turban with a peak over the forehead and crossing folds,
  /// sitting above the ears. Oval-head units.
  void _turban(Color color) {
    final shade = AvatarBrush.shade(color, .2);
    final deep = AvatarBrush.shade(color, .34);
    final light = AvatarBrush.tint(color, .22);
    final wrap = Path()
      ..moveTo(27.2, 44)
      ..cubicTo(22.6, 31, 26.4, 12.6, 50, 9.4)
      ..cubicTo(73.6, 12.6, 77.4, 31, 72.8, 44)
      ..quadraticBezierTo(63.6, 34.4, 50, 30.2)
      ..quadraticBezierTo(36.4, 34.4, 27.2, 44)
      ..close();
    b.path(wrap, color);

    _c.save();
    _c.clipPath(wrap);
    // Layers of cloth sweep up from each temple and cross at the front.
    final fold = b.line(shade, 1.1);
    for (final side in const [-1.0, 1.0]) {
      for (final (y, rise) in const [
        (41.0, 15.0),
        (35.0, 16.0),
        (28.0, 14.0),
      ]) {
        _c.drawPath(
          Path()
            ..moveTo(50 + side * 26, y)
            ..quadraticBezierTo(
              50 + side * 14,
              y - rise * .45,
              50 - side * 4,
              y - rise,
            ),
          fold,
        );
      }
    }
    // A soft highlight across the crown, and depth along the lower edge.
    b.stroke(
      Path()
        ..moveTo(36, 16.5)
        ..quadraticBezierTo(44, 12.4, 53, 12.2),
      light.withValues(alpha: .8),
      1.6,
    );
    b.stroke(
      Path()
        ..moveTo(27.2, 44)
        ..quadraticBezierTo(36.4, 34.4, 50, 30.2)
        ..quadraticBezierTo(63.6, 34.4, 72.8, 44),
      deep,
      1.8,
    );
    _c.restore();
  }

  static final _headscarves =
      <(double, double, double, double, double, double), _ScarfShapes>{};

  /// The headscarf and the face opening for [shape], built once per face
  /// shape.
  static _ScarfShapes _headscarfShapes(AvatarFaceShape shape) =>
      _headscarves.putIfAbsent((
        shape.halfWidth,
        shape.top,
        shape.cheekY,
        shape.chin,
        shape.jaw,
        shape.chinWidth,
      ), () => _buildHeadscarf(shape));

  static _ScarfShapes _buildHeadscarf(AvatarFaceShape shape) {
    final w = shape.halfWidth;
    final half = Path()
      ..moveTo(50, shape.top - 5.6)
      ..cubicTo(
        50 - w - 6.6,
        shape.top - 5.2,
        50 - w - 6.2,
        shape.cheekY - 8,
        50 - w - 4.6,
        shape.cheekY + 6,
      )
      ..cubicTo(50 - w - 3.4, shape.chin + 2, 28, 74, 22, 86.5)
      ..quadraticBezierTo(34, 95, 50, 95.6)
      ..close();
    final outer = AvatarBrush.union([half, AvatarBrush.mirrored(half)]);

    // The face shows through an opening just inside its outline, from the
    // forehead to under the chin.
    final inset = (w - 1.5) / w;
    final faceInset = shape.path.transform(
      Float64List.fromList([
        inset, 0, 0, 0, //
        0, 1, 0, 0,
        0, 0, 1, 0,
        50 - 50 * inset, -.6, 0, 1,
      ]),
    );
    final browLine = shape.top + 8.4;
    final opening = AvatarBrush.intersect(
      faceInset,
      Path()
        ..moveTo(0, browLine + 5)
        ..quadraticBezierTo(50, browLine - 5, 100, browLine + 5)
        ..lineTo(100, 140)
        ..lineTo(0, 140)
        ..close(),
    );
    final scarf = AvatarBrush.subtract(outer, opening);
    return (scarf: scarf, opening: opening);
  }

  /// A headscarf (hijab style) wrapping the hair, ears and neck, framing
  /// the face and falling over the shoulders. Drawn in avatar units over
  /// the finished face, with the opening following [shape].
  void drawHeadscarf(AvatarFaceShape shape, Color color) {
    final w = shape.halfWidth;
    final shade = AvatarBrush.shade(color, .16);
    final deep = AvatarBrush.shade(color, .3);
    final light = AvatarBrush.tint(color, .25);
    final (:scarf, :opening) = _headscarfShapes(shape);
    b.path(scarf, color);

    _c.save();
    _c.clipPath(scarf);
    // Shade where the cloth meets the face, and under the chin.
    b.stroke(opening, shade, 2.4);
    b.stroke(
      Path()
        ..moveTo(50 - w * .55, shape.chin + 2.6)
        ..quadraticBezierTo(
          50,
          shape.chin + 6.4,
          50 + w * .55,
          shape.chin + 2.6,
        ),
      shade.withValues(alpha: .6),
      1.2,
    );
    // Gentle folds in the drape and at the temples.
    final fold = b.line(shade, 1);
    for (final side in const [-1.0, 1.0]) {
      _c.drawPath(
        Path()
          ..moveTo(50 + side * (w - 2), shape.chin - 2)
          ..quadraticBezierTo(
            50 + side * (w + 1),
            80,
            50 + side * (w + 3.4),
            90,
          ),
        fold,
      );
      _c.drawPath(
        Path()
          ..moveTo(50 + side * 8, shape.chin + 11)
          ..quadraticBezierTo(50 + side * 9.6, 84, 50 + side * 8, 90),
        b.line(shade.withValues(alpha: .6), .8),
      );
      _c.drawPath(
        Path()
          ..moveTo(50 + side * (w + 3.6), shape.top + 6)
          ..quadraticBezierTo(
            50 + side * (w + 5),
            shape.cheekY,
            50 + side * (w + 2.8),
            shape.cheekY + 9,
          ),
        fold,
      );
    }
    b.stroke(
      Path()
        ..moveTo(37, shape.top - 1.6)
        ..quadraticBezierTo(44, shape.top - 4.4, 52, shape.top - 4.4),
      light.withValues(alpha: .85),
      1.6,
    );
    _c.restore();
    b.stroke(scarf, deep.withValues(alpha: .35), .7);
  }
}

typedef _ScarfShapes = ({Path scarf, Path opening});
