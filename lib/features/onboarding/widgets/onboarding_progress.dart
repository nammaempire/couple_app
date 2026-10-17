import 'package:flutter/material.dart';

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
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: s.index <= current
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
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
            ),
          ),
        ],
      ),
    );
  }
}
