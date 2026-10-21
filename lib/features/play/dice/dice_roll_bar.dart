import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/features/play/dice/game_dice.dart';

/// The die and what the last roll did, under a dice-game board.
///
/// Both players see who rolled what ([title]) and what came of it
/// ([detail]). The Roll button shows only when [onRoll] is set.
class DiceRollBar extends StatelessWidget {
  const DiceRollBar({
    super.key,
    required this.value,
    required this.rollId,
    required this.title,
    this.detail,
    this.rolling = false,
    this.accent,
    this.onRoll,
  });

  final int? value;
  final Object? rollId;
  final String title;
  final String? detail;
  final bool rolling;
  final Color? accent;
  final VoidCallback? onRoll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: GlassPanel(
        dark: theme.brightness == Brightness.dark,
        radius: 24,
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        child: Row(
          children: [
            GameDice(
              value: value,
              rollId: rollId,
              rolling: rolling,
              size: 52,
              accent: accent,
              onRoll: onRoll,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Column(
                  key: ValueKey('$title|$detail'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (onRoll != null) ...[
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const ValueKey('dice-roll-button'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  onRoll!();
                },
                icon: const Icon(Icons.casino_outlined, size: 20),
                label: const Text('Roll'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
