import 'package:flutter/rendering.dart';

import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/avatar/painting/avatar_accessory_painter.dart';
import 'package:couple_app/features/avatar/painting/avatar_brush.dart';
import 'package:couple_app/features/avatar/painting/avatar_face_painter.dart';
import 'package:couple_app/features/avatar/painting/avatar_hair_painter.dart';
import 'package:couple_app/features/avatar/painting/avatar_outfit_painter.dart';
import 'package:couple_app/features/avatar/painting/avatar_palette.dart';

/// Paints a whole avatar into a square. See [AvatarView] for the options.
class AvatarPainter extends CustomPainter {
  AvatarPainter({
    required this.config,
    required this.expression,
    this.showShoulders = true,
    this.showBackground = true,
    this.mirror = false,
  });

  final AvatarConfig config;
  final AvatarExpression expression;
  final bool showShoulders;
  final bool showBackground;
  final bool mirror;

  /// The part of the 100-unit avatar shown when only the head is drawn.
  static const headView = Rect.fromLTWH(14, 1, 72, 72);

  /// The figure is drawn a little smaller and higher than its design
  /// coordinates, leaving room for the outfit under the head.
  static const _figureScale = .93;
  static const _figureLift = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    if (side <= 0) return;
    final p = AvatarPalette.of(config);

    canvas.save();
    canvas.clipRect(Offset.zero & Size.square(side));
    if (mirror) {
      canvas
        ..translate(side, 0)
        ..scale(-1, 1);
    }
    if (showBackground) {
      final circle = Rect.fromLTWH(0, 0, side, side);
      canvas.drawOval(circle, Paint()..color = p.background);
      canvas.clipPath(Path()..addOval(circle));
    }

    final view = showShoulders ? const Rect.fromLTWH(0, 0, 100, 100) : headView;
    final scale = side / view.width;
    canvas
      ..scale(scale)
      ..translate(-view.left, -view.top)
      ..translate(50, 50 - _figureLift)
      ..scale(_figureScale)
      ..translate(-50, -50);

    _paintAvatar(AvatarBrush(canvas, pixelsPerUnit: scale * _figureScale), p);
    canvas.restore();
  }

  void _paintAvatar(AvatarBrush b, AvatarPalette p) {
    final canvas = b.canvas;
    final face = AvatarFacePainter(b, config, p, expression);
    final hair = AvatarHairPainter(b, config.hair, p);
    final outfit = AvatarOutfitPainter(b, config.outfit, p);
    final accessories = AvatarAccessoryPainter(
      b,
      p,
      earX: face.shape.left - .4,
    );
    final hat = AvatarAccessoryPainter.coversHair(config.accessory);
    final hairHidden = AvatarAccessoryPainter.hidesAllHair(config.accessory);

    void inHeadSpace(void Function() draw, {bool underHat = false}) {
      canvas.save();
      canvas.transform(face.shape.hairTransform);
      if (underHat && hat) {
        canvas.clipPath(AvatarAccessoryPainter.hairClip(config.accessory));
      }
      draw();
      canvas.restore();
    }

    if (!hairHidden) inHeadSpace(hair.drawBack, underHat: true);
    if (showShoulders) {
      outfit.drawBack();
      face.drawNeck();
      outfit.drawFront();
    } else {
      face.drawNeck();
    }
    face
      ..drawEars()
      ..drawHead()
      ..drawCheeks()
      ..drawFacialHair();
    _boosted(
      canvas,
      b,
      () => face
        ..drawNose()
        ..drawMouth(),
    );
    face.drawMoustache();
    _boosted(
      canvas,
      b,
      () => face
        ..drawEyes()
        ..drawBrows(),
    );
    accessories.drawOnFace(config.accessory, bindi: config.hasBindi);
    if (!hairHidden) inHeadSpace(hair.drawFront, underHat: true);
    accessories.drawGlasses(config.glasses);
    inHeadSpace(() => accessories.drawOnHair(config.accessory, p.outfit));
    if (config.accessory == 'headscarf') {
      accessories.drawHeadscarf(face.shape, p.scarf);
    }
    face.drawExtras();
  }

  /// Small avatars get slightly larger eyes, brows and mouth so faces
  /// still read at chat-avatar sizes.
  static void _boosted(Canvas canvas, AvatarBrush b, void Function() draw) {
    final boost = ((.8 - b.pixelsPerUnit) / .35).clamp(0.0, 1.0) * .14;
    canvas.save();
    if (boost > 0) {
      canvas
        ..translate(50, 52)
        ..scale(1 + boost)
        ..translate(-50, -52);
    }
    draw();
    canvas.restore();
  }

  @override
  bool shouldRepaint(AvatarPainter old) =>
      old.config != config ||
      old.expression != expression ||
      old.showShoulders != showShoulders ||
      old.showBackground != showBackground ||
      old.mirror != mirror;
}
