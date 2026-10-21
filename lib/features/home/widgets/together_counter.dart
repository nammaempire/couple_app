import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/couple/models/couple.dart';

/// Days together (with a years/months/days breakdown) and the next
/// round-number milestone. The meetup countdown lives in "Coming up".
class TogetherCounter extends StatelessWidget {
  const TogetherCounter({
    super.key,
    required this.couple,
    required this.onSetStartDate,
  });

  final Couple couple;
  final VoidCallback onSetStartDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = couple.daysTogether;

    if (days == null) {
      return _CounterCard(
        child: Column(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(height: 12),
            Text(
              'When did you two start?',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Set your date to start counting.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer.withValues(
                  alpha: .75,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onSetStartDate,
              child: const Text('Set our date'),
            ),
          ],
        ),
      );
    }

    final milestone = couple.nextMilestone;
    final breakdown = couple.togetherBreakdown();
    final breakdownLabel = breakdown == null
        ? null
        : _breakdownLabel(breakdown);

    return _CounterCard(
      child: Column(
        children: [
          Text(
            'Together for',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer.withValues(alpha: .8),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                NumberFormat.decimalPattern().format(days),
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                days == 1 ? 'day' : 'days',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer.withValues(
                    alpha: .8,
                  ),
                ),
              ),
            ],
          ),
          if (breakdownLabel != null) ...[
            const SizedBox(height: 2),
            Text(
              breakdownLabel,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (couple.startDate != null) ...[
            const SizedBox(height: 2),
            Text(
              'since ${DateFormat.yMMMMd().format(couple.startDate!)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer.withValues(
                  alpha: .7,
                ),
              ),
            ),
          ],
          if (milestone != null) ...[
            const SizedBox(height: 16),
            _MilestoneChip(
              icon: Icons.celebration_outlined,
              label: milestone.daysAway == 0
                  ? '${milestone.milestone} days — today!'
                  : '${milestone.daysAway} days to ${milestone.milestone}',
            ),
          ],
        ],
      ),
    );
  }

  /// "2 years · 3 months · 5 days", leaving out leading zero units. Returns
  /// null under a month, where it would only repeat the day count.
  static String? _breakdownLabel(({int years, int months, int days}) b) {
    if (b.years == 0 && b.months == 0) return null;
    String unit(int n, String word) => '$n ${n == 1 ? word : '${word}s'}';
    return [
      if (b.years > 0) unit(b.years, 'year'),
      if (b.years > 0 || b.months > 0) unit(b.months, 'month'),
      unit(b.days, 'day'),
    ].join(' · ');
  }
}

class _CounterCard extends StatelessWidget {
  const _CounterCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedGradientCard(
      preset: GradientPreset.blush,
      radius: 26,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          Positioned.fill(
            child: FloatingHearts(count: 9, seed: 3, opacity: dark ? .22 : .75),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            child: Center(child: child),
          ),
        ],
      ),
    );
  }
}

class _MilestoneChip extends StatelessWidget {
  const _MilestoneChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 7),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
