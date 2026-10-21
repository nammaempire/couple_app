import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/widgets/play_look.dart';

/// One game in a hub list: emoji, name, status and when it last moved.
class PlayGameRow extends StatelessWidget {
  const PlayGameRow({
    super.key,
    required this.game,
    required this.status,
    required this.time,
    this.emphasised = false,
    this.onTap,
    this.actions,
  });

  final Game game;
  final String status;
  final String time;

  /// Draws the status in the accent colour (something for me to do).
  final bool emphasised;
  final VoidCallback? onTap;

  /// Optional buttons under the text, such as Accept / Not now.
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final preset = PlayLook.of(game.type);
    final accent = emphasised ? scheme.primary : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: AnimatedGradientCard(
        preset: preset,
        colors: emphasised
            ? null
            : [
                scheme.surfaceContainerLow,
                scheme.surfaceContainerLow,
                Color.alphaBlend(
                  preset.colors(theme.brightness)[1].withValues(alpha: .35),
                  scheme.surfaceContainerLow,
                ),
              ],
        animate: emphasised,
        sheen: false,
        shadow: emphasised,
        onTap: onTap,
        radius: 20,
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: dark ? .12 : .8),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    game.type.emoji,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.type.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: accent,
                          fontWeight: emphasised ? FontWeight.w700 : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (time.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    time,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            if (actions != null) ...[
              const SizedBox(height: 10),
              Padding(padding: const EdgeInsets.only(left: 56), child: actions),
            ],
          ],
        ),
      ),
    );
  }
}
