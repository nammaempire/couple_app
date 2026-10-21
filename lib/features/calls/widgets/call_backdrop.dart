import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';

/// The deep rose-to-violet backdrop behind the call screens: a slowly
/// drifting gradient, a soft glow behind the avatar and a few rising
/// hearts. Still when motion is off.
class CallBackdrop extends StatelessWidget {
  const CallBackdrop({super.key, required this.child});

  final Widget child;

  /// Dark enough everywhere for white text (well past AA).
  static const colors = [
    Color(0xFF5A1E44),
    Color(0xFF33204F),
    Color(0xFF140F26),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedGradientBackground(
      colors: colors,
      duration: const Duration(seconds: 12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -.35),
                radius: .75,
                colors: [Color(0x55FF6FA5), Color(0x00FF6FA5)],
              ),
            ),
          ),
          const FloatingHearts(
            color: Color(0xFFFFB3CF),
            count: 12,
            opacity: .35,
            seed: 11,
          ),
          child,
        ],
      ),
    );
  }
}
