import 'package:flutter/material.dart';

import 'package:couple_app/features/play/board/connect_four_logic.dart';

/// A red or yellow disc; an empty hole when [color] is `''`.
class ConnectFourDisc extends StatelessWidget {
  const ConnectFourDisc({
    super.key,
    required this.color,
    this.highlight = false,
    this.ring = false,
  });

  final String color;

  /// Part of the winning four.
  final bool highlight;

  /// The last disc dropped.
  final bool ring;

  static const _red = Color(0xFFE05C7B);
  static const _yellow = Color(0xFFF5B83D);

  static Color fill(String color, ColorScheme scheme) => switch (color) {
    ConnectFourLogic.red => _red,
    ConnectFourLogic.yellow => _yellow,
    _ => scheme.surface,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = fill(color, scheme);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: base,
        gradient: color.isEmpty
            ? null
            : RadialGradient(
                center: const Alignment(-0.3, -0.4),
                colors: [Color.lerp(base, Colors.white, 0.35)!, base],
              ),
        border: Border.all(
          color: highlight
              ? scheme.onSurface
              : ring
              ? scheme.onSurface.withValues(alpha: 0.45)
              : Colors.transparent,
          width: highlight ? 3 : 2,
        ),
        boxShadow: highlight
            ? [BoxShadow(color: base.withValues(alpha: 0.6), blurRadius: 10)]
            : null,
      ),
    );
  }
}
