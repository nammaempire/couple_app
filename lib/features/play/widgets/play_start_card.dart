import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';

import 'package:couple_app/features/play/game_catalog.dart';
import 'package:couple_app/features/play/models/game.dart';

/// A game you can start: emoji, name and one line about it.
class PlayStartCard extends StatelessWidget {
  const PlayStartCard({
    super.key,
    required this.type,
    this.inProgress = false,
    this.busy = false,
    this.onTap,
  });

  final GameType type;

  /// There is already an open game of this type.
  final bool inProgress;

  /// The invite is being sent.
  final bool busy;

  /// Null disables the card.
  final VoidCallback? onTap;

  /// Each game gets its own soft gradient.
  static GradientPreset presetFor(GameType type) => switch (type) {
    GameType.knowMe => GradientPreset.lavender,
    GameType.truthOrDare => GradientPreset.sunset,
    GameType.ticTacToe => GradientPreset.ocean,
    GameType.connectFour => GradientPreset.peach,
    GameType.ludo => GradientPreset.mint,
    _ => GradientPreset.sunny,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: AnimatedGradientCard(
        preset: presetFor(type),
        onTap: busy ? null : onTap,
        animate: enabled,
        radius: 22,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(
                      alpha: theme.brightness == Brightness.dark ? .12 : .7,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(type.emoji, style: const TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 8),
                const Spacer(),
                if (busy)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (inProgress)
                  Flexible(
                    flex: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: .75),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Playing',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              type.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              GameCatalog.blurb(type),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
