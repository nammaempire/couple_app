import 'package:flutter/material.dart';

import 'package:couple_app/features/play/models/game.dart';

/// One calm line under a board: what to do now, or who we're waiting on.
class BoardTurnHint extends StatelessWidget {
  const BoardTurnHint({
    super.key,
    required this.game,
    required this.myUid,
    required this.partnerName,
    required this.yourTurnText,
    this.busy = false,
  });

  final Game game;
  final String myUid;
  final String partnerName;
  final String yourTurnText;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final waiting = game.isActive && game.turn != myUid;
    final String text;
    if (game.isFinished) {
      text = game.isDraw
          ? 'Evenly matched. Fancy a rematch?'
          : game.winner == myUid
          ? 'Nicely played!'
          : 'Good game. Your revenge awaits.';
    } else if (busy) {
      text = 'Sending your move…';
    } else if (waiting) {
      text = 'Waiting for $partnerName to move…';
    } else {
      text = yourTurnText;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Row(
          key: ValueKey(text),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (waiting || busy) ...[
              Icon(Icons.hourglass_top_rounded, size: 16, color: color),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
