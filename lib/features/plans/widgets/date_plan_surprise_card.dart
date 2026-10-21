import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';

/// A festive banner at the top of the ideas list that picks a random idea.
class DatePlanSurpriseCard extends StatelessWidget {
  const DatePlanSurpriseCard({
    super.key,
    required this.ideaCount,
    required this.onSurprise,
  });

  final int ideaCount;
  final VoidCallback onSurprise;

  static const preset = GradientPreset.festive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: AnimatedGradientCard(
        preset: preset,
        radius: 26,
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: FloatingHearts(
                  count: 7,
                  seed: 3,
                  style: ParticleStyle.confetti,
                  opacity: preset.isDarkIn(b) ? .35 : .5,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Bobbing(
                    amplitude: 3,
                    tilt: .08,
                    child: Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: preset.isDarkIn(b) ? .14 : .7,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text('🎲', style: TextStyle(fontSize: 28)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Can\'t decide?',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: preset.foreground(b),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ideaCount == 1
                              ? 'You have one idea waiting.'
                              : 'We\'ll pick one of your $ideaCount ideas.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: preset.foregroundMuted(b),
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: onSurprise,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 42),
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            shape: const StadiumBorder(),
                          ),
                          icon: const Icon(Icons.casino_outlined, size: 18),
                          label: const Text('Surprise me'),
                        ),
                      ],
                    ),
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
