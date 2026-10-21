import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/plans/models/bucket_progress.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';

/// A soft card with "12 of 40 done" and a progress bar.
class BucketProgressHeader extends StatelessWidget {
  const BucketProgressHeader({
    super.key,
    required this.progress,
    this.categoryLabel,
  });

  final BucketProgress progress;

  /// The category being filtered on, if any.
  final String? categoryLabel;

  String get _caption {
    if (progress.total == 0) return 'Nothing here yet';
    if (progress.isComplete) return 'Every single one. You two are amazing.';
    if (progress.done == 0) return 'Your adventures are waiting';
    if (progress.remaining == 1) return 'Just one more to go';
    return '${progress.remaining} still to go';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final b = theme.brightness;
    final preset = progress.isComplete
        ? GradientPreset.gold
        : GradientPreset.sunny;
    final fg = preset.foreground(b);
    final fgMuted = preset.foregroundMuted(b);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: AnimatedGradientCard(
        preset: preset,
        radius: 26,
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            Positioned(
              right: -6,
              top: -10,
              child: ExcludeSemantics(
                child: Text(
                  progress.isComplete ? '🏆' : '🌟',
                  style: TextStyle(
                    fontSize: 72,
                    color: Colors.white.withValues(alpha: .9),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 64),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          categoryLabel ?? 'OUR BUCKET LIST',
                          style: categoryLabel == null
                              ? theme.textTheme.labelSmall?.copyWith(
                                  color: presetAccentText(preset, b),
                                  letterSpacing: 1.3,
                                  fontWeight: FontWeight.w800,
                                )
                              : theme.textTheme.labelLarge?.copyWith(
                                  color: fgMuted,
                                ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          progress.label,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: fg,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: GradientProgressBar(
                          fraction: progress.fraction,
                          preset: preset,
                          height: 12,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${progress.percent}%',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _caption,
                    style: theme.textTheme.bodyMedium?.copyWith(color: fgMuted),
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
