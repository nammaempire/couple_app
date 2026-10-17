import 'package:flutter/material.dart';

import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/avatar/painting/avatar_painter.dart';

/// Draws [config] at [size] (the width; height is the same) with
/// [expression]. Everything is painted with shapes, so it stays crisp at
/// any size.
class AvatarView extends StatelessWidget {
  const AvatarView({
    super.key,
    required this.config,
    this.expression = AvatarExpression.neutral,
    this.size = 96,
    this.showShoulders = true,
    this.showBackground = true,
    this.mirror = false,
  });

  final AvatarConfig config;
  final AvatarExpression expression;
  final double size;

  /// Draw the neck, shoulders and outfit under the head.
  final bool showShoulders;

  /// Fill a circle behind the avatar with its background colour.
  final bool showBackground;

  /// Flip horizontally, so two avatars can face each other in a sticker.
  final bool mirror;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: AvatarPainter(
        config: config,
        expression: expression,
        showShoulders: showShoulders,
        showBackground: showBackground,
        mirror: mirror,
      ),
    ),
  );
}
