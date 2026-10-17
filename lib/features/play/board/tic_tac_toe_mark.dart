import 'package:flutter/material.dart';

import 'package:couple_app/features/play/board/tic_tac_toe_logic.dart';

/// An X or an O in the board's colours.
class TicTacToeMark extends StatelessWidget {
  const TicTacToeMark({super.key, required this.mark, this.size = 20});

  final String mark;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FittedBox(
      child: Text(
        mark,
        style: TextStyle(
          fontSize: size,
          height: 1,
          fontWeight: FontWeight.w800,
          color: mark == TicTacToeLogic.x ? scheme.primary : scheme.tertiary,
        ),
      ),
    );
  }
}
