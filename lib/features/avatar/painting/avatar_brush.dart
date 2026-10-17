import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// A canvas in avatar units (the avatar is drawn in a 100 × 100 box) with
/// small paint helpers shared by the avatar painters.
class AvatarBrush {
  AvatarBrush(this.canvas, {required this.pixelsPerUnit});

  final Canvas canvas;

  /// How many device-independent pixels one avatar unit covers.
  final double pixelsPerUnit;

  /// Large enough for fine details such as seams, buttons and knit ribs.
  bool get detailed => pixelsPerUnit >= .8;

  /// Thinnest line, in units, that still reads on screen (about 0.9 px).
  double get hairline => .9 / pixelsPerUnit;

  Paint fill(Color color) => Paint()
    ..color = color
    ..isAntiAlias = true;

  Paint line(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(width, hairline)
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  void path(Path path, Color color) => canvas.drawPath(path, fill(color));

  void stroke(Path path, Color color, double width) =>
      canvas.drawPath(path, line(color, width));

  void oval(double cx, double cy, double rx, double ry, Color color) =>
      canvas.drawOval(ovalRect(cx, cy, rx, ry), fill(color));

  void circle(double cx, double cy, double r, Color color) =>
      canvas.drawCircle(Offset(cx, cy), r, fill(color));

  static Rect ovalRect(double cx, double cy, double rx, double ry) =>
      Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2);

  static Path ovalPath(double cx, double cy, double rx, double ry) =>
      Path()..addOval(ovalRect(cx, cy, rx, ry));

  static Path circlePath(double cx, double cy, double r) =>
      ovalPath(cx, cy, r, r);

  /// A heart [width] units wide, centred on ([cx], [cy]).
  static Path heart(double cx, double cy, double width) {
    final s = width / 2;
    return Path()
      ..moveTo(cx, cy + s * .92)
      ..cubicTo(
        cx - s * 1.25,
        cy + s * .12,
        cx - s * 1.1,
        cy - s * 1.05,
        cx,
        cy - s * .42,
      )
      ..cubicTo(
        cx + s * 1.1,
        cy - s * 1.05,
        cx + s * 1.25,
        cy + s * .12,
        cx,
        cy + s * .92,
      )
      ..close();
  }

  /// Everything above [hairline], which must run from x = 0 to x = 100.
  static Path above(Path hairline) => hairline
    ..lineTo(100, -40)
    ..lineTo(0, -40)
    ..close();

  static Path union(Iterable<Path> paths) =>
      paths.reduce((a, b) => Path.combine(PathOperation.union, a, b));

  static Path intersect(Path a, Path b) =>
      Path.combine(PathOperation.intersect, a, b);

  static Path subtract(Path a, Path b) =>
      Path.combine(PathOperation.difference, a, b);

  /// [path] mirrored across the avatar's centre line.
  static Path mirrored(Path path) => path.transform(
    Float64List.fromList([-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 100, 0, 0, 1]),
  );

  /// [color] mixed towards a warm near-black by [amount].
  static Color shade(Color color, double amount) =>
      Color.lerp(color, const Color(0xFF1A0E0A), amount)!;

  /// [color] mixed towards white by [amount].
  static Color tint(Color color, double amount) =>
      Color.lerp(color, const Color(0xFFFFFFFF), amount)!;
}
