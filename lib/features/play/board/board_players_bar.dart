import 'package:flutter/material.dart';

import 'package:couple_app/features/play/models/game.dart';

/// "You (X) vs Ravi (O)" above a board, lighting up whoever is to move.
class BoardPlayersBar extends StatelessWidget {
  const BoardPlayersBar({
    super.key,
    required this.game,
    required this.myUid,
    required this.partnerName,
    required this.myToken,
    required this.partnerToken,
  });

  final Game game;
  final String myUid;
  final String partnerName;
  final Widget myToken;
  final Widget partnerToken;

  @override
  Widget build(BuildContext context) {
    final partner = game.opponentOf(myUid);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: _PlayerChip(
              name: 'You',
              token: myToken,
              active: game.isActive && game.turn == myUid,
              won: game.isFinished && game.winner == myUid,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'vs',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: _PlayerChip(
              name: partnerName,
              token: partnerToken,
              active: game.isActive && game.turn == partner,
              won: game.isFinished && game.winner == partner,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  const _PlayerChip({
    required this.name,
    required this.token,
    required this.active,
    required this.won,
  });

  final String name;
  final Widget token;
  final bool active;
  final bool won;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highlighted = active || won;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? scheme.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(dimension: 22, child: Center(child: token)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
                color: highlighted
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (won) ...[
            const SizedBox(width: 4),
            const Text('🏆', style: TextStyle(fontSize: 14)),
          ],
        ],
      ),
    );
  }
}
