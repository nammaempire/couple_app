import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/music/widgets/on_gradient_theme.dart';
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

  static const boardGames = [
    GameType.ticTacToe,
    GameType.connectFour,
    GameType.ludo,
    GameType.snakesLadders,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = HeadToHead.from(games);
    final mine = all.winsFor(myUid);
    final theirs = all.winsFor(partnerUid);
    final leader = mine == theirs
        ? 'Neck and neck'
        : mine > theirs
        ? 'You\'re ahead'
        : '$partnerName is ahead';

    const preset = GradientPreset.gold;
    final b = theme.brightness;
    final dark = b == Brightness.dark;
    final fg = preset.foreground(b);
    final muted = preset.foregroundMuted(b);
    final ink = OnGradientTheme.ink(preset, b);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: AnimatedGradientCard(
        preset: preset,
        radius: 24,
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            const Positioned.fill(
              child: FloatingHearts(
                style: ParticleStyle.confetti,
                count: 8,
                opacity: .45,
                seed: 21,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _Score(
                          label: 'You',
                          wins: mine,
                          color: ink,
                          labelColor: fg,
                        ),
                      ),
                      Column(
                        children: [
                          Pulse(
                            duration: const Duration(milliseconds: 2400),
                            builder: (context, v, child) => Transform.scale(
                              scale: 1 + v * .08,
                              child: child,
                            ),
                            child: Container(
                              width: 48,
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(
                                  alpha: dark ? .14 : .75,
                                ),
                              ),
                              child: const Text(
                                '🏆',
                                style: TextStyle(fontSize: 26),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            leader,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: fg,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                        child: _Score(
                          label: partnerName,
                          wins: theirs,
                          color: ink,
                          labelColor: fg,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${all.played} played · ${all.draws} '
                    '${all.draws == 1 ? 'draw' : 'draws'}',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  Divider(height: 24, color: fg.withValues(alpha: .15)),
                  for (final type in boardGames)
                    _BreakdownRow(
                      type: type,
                      tally: HeadToHead.from(games, type: type),
                      myUid: myUid,
                      partnerUid: partnerUid,
                      partnerName: partnerName,
                      fg: fg,
                      muted: muted,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Score extends StatelessWidget {
  const _Score({
    required this.label,
    required this.wins,
    required this.color,
    required this.labelColor,
  });

  final String label;
  final int wins;
  final Color color;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          '$wins',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            color: labelColor,
            fontWeight: FontWeight.w700,
          ),
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
    required this.fg,
    required this.muted,
  });

  final Color fg;
  final Color muted;
  final GameType type;
  final HeadToHead tally;
  final String myUid;
  final String partnerUid;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              style: theme.textTheme.bodyMedium?.copyWith(color: fg),
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
