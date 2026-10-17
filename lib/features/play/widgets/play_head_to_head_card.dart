import 'package:flutter/material.dart';

import 'package:couple_app/features/play/models/game.dart';

/// You vs your partner: wins, draws and games played, plus a line for
/// each board game.
class PlayHeadToHeadCard extends StatelessWidget {
  const PlayHeadToHeadCard({
    super.key,
    required this.games,
    required this.myUid,
    required this.partnerUid,
    required this.partnerName,
  });

  final List<Game> games;
  final String myUid;
  final String partnerUid;
  final String partnerName;

  static const boardGames = [GameType.ticTacToe, GameType.connectFour];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final all = HeadToHead.from(games);
    final mine = all.winsFor(myUid);
    final theirs = all.winsFor(partnerUid);
    final leader = mine == theirs
        ? 'Neck and neck'
        : mine > theirs
        ? 'You\'re ahead'
        : '$partnerName is ahead';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      color: scheme.secondaryContainer.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _Score(label: 'You', wins: mine),
                ),
                Column(
                  children: [
                    Text('🏆', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      leader,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: _Score(label: partnerName, wins: theirs),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${all.played} played · ${all.draws} '
              '${all.draws == 1 ? 'draw' : 'draws'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
            const Divider(height: 24),
            for (final type in boardGames)
              _BreakdownRow(
                type: type,
                tally: HeadToHead.from(games, type: type),
                myUid: myUid,
                partnerUid: partnerUid,
                partnerName: partnerName,
              ),
          ],
        ),
      ),
    );
  }
}

class _Score extends StatelessWidget {
  const _Score({required this.label, required this.wins});

  final String label;
  final int wins;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          '$wins',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge,
        ),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.type,
    required this.tally,
    required this.myUid,
    required this.partnerUid,
    required this.partnerName,
  });

  final GameType type;
  final HeadToHead tally;
  final String myUid;
  final String partnerUid;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSecondaryContainer;
    final text = tally.played == 0
        ? 'Not played yet'
        : 'You ${tally.winsFor(myUid)} · $partnerName '
              '${tally.winsFor(partnerUid)}'
              '${tally.draws > 0 ? ' · ${tally.draws} drawn' : ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(type.emoji),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              type.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: Text(
              text,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
        ],
      ),
    );
  }
}
