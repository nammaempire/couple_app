import 'dart:typed_data';
import 'dart:ui';

/// The head outline for one face shape, in avatar units. Hair and hats are
/// designed for the oval head (21 units half-width, top at 23) and are
/// stretched to fit the others with [hairTransform].
class AvatarFaceShape {
  const AvatarFaceShape._({
    required this.halfWidth,
    required this.top,
    required this.cheekY,
    required this.chin,
    required this.jaw,
    required this.chinWidth,
  });

  factory AvatarFaceShape.of(String id) => switch (id) {
    'round' => const AvatarFaceShape._(
      halfWidth: 22.2,
      top: 23.4,
      cheekY: 47,
      chin: 67,
      jaw: .78,
      chinWidth: 12,
    ),
    'heart' => const AvatarFaceShape._(
      halfWidth: 21.8,
      top: 23,
      cheekY: 44.5,
      chin: 67.6,
      jaw: .32,
      chinWidth: 3.6,
    ),
    'square' => const AvatarFaceShape._(
      halfWidth: 21.4,
      top: 23,
      cheekY: 46,
      chin: 67.4,
      jaw: .95,
      chinWidth: 13.5,
    ),
    'long' => const AvatarFaceShape._(
      halfWidth: 19.8,
      top: 21.6,
      cheekY: 46,
      chin: 70,
      jaw: .55,
      chinWidth: 8,
    ),
    _ => const AvatarFaceShape._(
      halfWidth: 21,
      top: 23,
      cheekY: 46,
      chin: 68,
      jaw: .58,
      chinWidth: 9,
    ),
  };

  final double halfWidth;
  final double top;

  /// Height of the widest point.
  final double cheekY;
  final double chin;

  /// 0 tapers straight to the chin, 1 keeps the jaw square.
  final double jaw;
  final double chinWidth;

  double get left => 50 - halfWidth;
  double get right => 50 + halfWidth;

  Path get path {
    final w = halfWidth;
    final upper = top + (cheekY - top) * .42;
    final lower = cheekY + (chin - cheekY) * jaw;
    return Path()
      ..moveTo(50, top)
      ..cubicTo(50 + w * .58, top, 50 + w, upper, 50 + w, cheekY)
      ..cubicTo(50 + w, lower, 50 + chinWidth, chin, 50, chin)
      ..cubicTo(50 - chinWidth, chin, 50 - w, lower, 50 - w, cheekY)
      ..cubicTo(50 - w, upper, 50 - w * .58, top, 50, top)
      ..close();
  }

  /// Maps hair designed for the oval head onto this one.
  Float64List get hairTransform {
    final sx = halfWidth / 21;
    final dy = top - 23;
    return Float64List.fromList([
      sx, 0, 0, 0, //
      0, 1, 0, 0,
      0, 0, 1, 0,
      50 - 50 * sx, dy, 0, 1,
    ]);
  }
}
