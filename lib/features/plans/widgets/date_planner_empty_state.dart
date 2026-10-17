import 'package:flutter/material.dart';

import 'package:couple_app/features/plans/models/date_plan.dart';

/// Friendly empty state for one segment of the date planner.
class DatePlannerEmptyState extends StatelessWidget {
  const DatePlannerEmptyState({
    super.key,
    required this.status,
    required this.partnerName,
    required this.onAdd,
  });

  final DatePlanStatus status;
  final String partnerName;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, title, hint, button) = switch (status) {
      DatePlanStatus.idea => (
        Icons.lightbulb_outline,
        'No date ideas yet',
        'Jot down anything you and $partnerName might love: a new café, a '
            'sunrise walk, a cooking night.',
        'Add an idea',
      ),
      DatePlanStatus.planned => (
        Icons.event_outlined,
        'Nothing planned yet',
        'Pick an idea and give it a date. It shows up on your calendar too.',
        'Plan a date',
      ),
      DatePlanStatus.done => (
        Icons.favorite_outline,
        'Your first date story goes here',
        'Mark a planned date as done to keep hearts and a few words about '
            'how it went.',
        null,
      ),
    };

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: .6),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (button != null) ...[
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(button),
            ),
          ],
        ],
      ),
    );
  }
}
