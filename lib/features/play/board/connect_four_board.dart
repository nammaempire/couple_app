import 'package:flutter/material.dart';

import 'package:couple_app/features/play/board/connect_four_disc.dart';
import 'package:couple_app/features/play/board/connect_four_logic.dart';

/// The 7×6 board. Tapping anywhere in a column calls [onDrop] with it.
///
/// The last disc dropped falls into place; the winning four glow.
class ConnectFourBoard extends StatelessWidget {
  const ConnectFourBoard({
    super.key,
    required this.board,
    this.lastMove = -1,
    this.moveCount = 0,
    this.winningCells,
    this.onDrop,
  });

  final List<String> board;
  final int lastMove;

  /// Replays the drop animation once per move.
  final int moveCount;
  final List<int>? winningCells;

  /// Null disables the board.
  final ValueChanged<int>? onDrop;

  static const _gap = 5.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final winning = winningCells?.toSet() ?? const <int>{};
    return AspectRatio(
      aspectRatio: ConnectFourLogic.cols / ConnectFourLogic.rows,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(22),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cell = constraints.maxHeight / ConnectFourLogic.rows;
            return ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Row(
                children: [
                  for (var col = 0; col < ConnectFourLogic.cols; col++)
                    Expanded(child: _column(context, col, cell, winning)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _column(BuildContext context, int col, double cell, Set<int> winning) {
    final full = ConnectFourLogic.dropRow(board, col) == null;
    final enabled = onDrop != null && !full;
    return Semantics(
      button: enabled,
      label: full ? 'Column ${col + 1}, full' : 'Drop in column ${col + 1}',
      child: InkWell(
        key: ValueKey('c4-col-$col'),
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? () => onDrop!(col) : null,
        child: Column(
          children: [
            for (var row = 0; row < ConnectFourLogic.rows; row++)
              Expanded(child: _cell(row, col, cell, winning)),
          ],
        ),
      ),
    );
  }

  Widget _cell(int row, int col, double cell, Set<int> winning) {
    final i = ConnectFourLogic.index(row, col);
    final color = board[i];
    Widget disc = ConnectFourDisc(
      color: color,
      highlight: winning.contains(i),
      ring: i == lastMove && winning.isEmpty,
    );
    if (i == lastMove && color.isNotEmpty) {
      // Fall from above the board into this row.
      disc = TweenAnimationBuilder<double>(
        key: ValueKey('drop-$i-$moveCount'),
        tween: Tween(begin: -(row + 1) * cell, end: 0),
        duration: Duration(milliseconds: 220 + row * 55),
        curve: Curves.bounceOut,
        builder: (context, dy, child) =>
            Transform.translate(offset: Offset(0, dy), child: child),
        child: disc,
      );
      disc = Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          const ConnectFourDisc(color: ''),
          disc,
        ],
      );
    }
    return Padding(padding: const EdgeInsets.all(_gap / 2), child: disc);
  }
}
