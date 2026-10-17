import 'package:flutter/material.dart';

import 'package:couple_app/features/play/board/tic_tac_toe_logic.dart';
import 'package:couple_app/features/play/board/tic_tac_toe_mark.dart';

/// The 3×3 grid. Pure presentation: taps go to [onTap] when it is set.
class TicTacToeBoard extends StatelessWidget {
  const TicTacToeBoard({
    super.key,
    required this.board,
    this.lastMove = -1,
    this.winningLine,
    this.pendingCell,
    this.pendingMark,
    this.onTap,
  });

  final List<String> board;
  final int lastMove;
  final List<int>? winningLine;

  /// A move on its way to the server, drawn faintly.
  final int? pendingCell;
  final String? pendingMark;

  /// Null disables every cell.
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(28),
        ),
        child: GridView.count(
          crossAxisCount: TicTacToeLogic.size,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          children: [
            for (var i = 0; i < TicTacToeLogic.cells; i++) _cell(context, i),
          ],
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, int i) {
    final scheme = Theme.of(context).colorScheme;
    final mark = board[i];
    final winning = winningLine?.contains(i) ?? false;
    final pending = mark.isEmpty && pendingCell == i;
    final shown = pending ? (pendingMark ?? '') : mark;
    final enabled = onTap != null && mark.isEmpty && pendingCell == null;

    return Semantics(
      button: enabled,
      label: mark.isEmpty ? 'Empty square ${i + 1}' : '$mark, square ${i + 1}',
      child: Material(
        key: ValueKey('ttt-cell-$i'),
        color: winning ? scheme.primaryContainer : scheme.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () => onTap!(i) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: winning
                    ? scheme.primary
                    : i == lastMove
                    ? scheme.outline.withValues(alpha: 0.6)
                    : Colors.transparent,
                width: winning ? 2.5 : 1.5,
              ),
            ),
            child: Center(
              child: shown.isEmpty
                  ? const SizedBox.shrink()
                  : Opacity(
                      opacity: pending ? 0.35 : 1,
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey('$i$shown'),
                        tween: Tween(begin: 0.4, end: 1),
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutBack,
                        builder: (context, scale, child) =>
                            Transform.scale(scale: scale, child: child),
                        child: TicTacToeMark(mark: shown, size: 52),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
