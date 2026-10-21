import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';

/// The three onboarding stages, shown as a slim segmented bar.
enum OnboardingStep {
  profile('About you'),
  space('Your space'),
  invite('Invite');

  const OnboardingStep(this.label);
  final String label;
}

class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({super.key, required this.step});

  final OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = step.index;
    final n = OnboardingStep.values.length;
    final b = theme.brightness;
    final dark = b == Brightness.dark;
    final from = dark
        ? GradientPreset.blush.accent(b)
        : GradientPreset.blush.ink;
    final to = dark
        ? GradientPreset.lavender.accent(b)
        : GradientPreset.lavender.ink;

    return Semantics(
      label:
          'Step ${current + 1} of ${OnboardingStep.values.length}: '
          '${step.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final s in OnboardingStep.values) ...[
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: s.index <= current
                          ? null
                          : theme.colorScheme.onSurface.withValues(alpha: .1),
                      gradient: s.index <= current
                          ? LinearGradient(
                              colors: [
                                Color.lerp(from, to, s.index / n)!,
                                Color.lerp(from, to, (s.index + 1) / n)!,
                              ],
                            )
                          : null,
                    ),
                  ),
                ),
                if (s != OnboardingStep.values.last) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Step ${current + 1} of ${OnboardingStep.values.length} · '
            '${step.label}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: .3,
            ),
          ),
        ],
      ),
    );
  }
}
