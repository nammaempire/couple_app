import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/home/models/important_date.dart';

/// The next important date as a big countdown, with the two after it below.
class ComingUpCard extends StatelessWidget {
  const ComingUpCard({
    super.key,
    required this.dates,
    required this.onAddDates,
    this.onSeeCalendar,
  });

  /// Soonest first.
  final List<ImportantDate> dates;

  /// Adds a calendar event.
  final VoidCallback onAddDates;

  /// Opens the full calendar.
  final VoidCallback? onSeeCalendar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (dates.isEmpty) {
      return _ComingUpSurface(
        child: Row(
          children: [
            Icon(Icons.event_outlined, color: scheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No dates yet',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Plan a date or add birthdays and your anniversary to '
                    'count down here.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onAddDates, child: const Text('Add')),
          ],
        ),
      );
    }

    final next = dates.first;
    final later = dates.skip(1).take(2).toList();

    return _ComingUpSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'COMING UP',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onSeeCalendar != null)
                InkWell(
                  onTap: onSeeCalendar,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      'Calendar',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 64,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    Text(
                      next.daysAway == 0 ? '🎉' : '${next.daysAway}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      next.daysAway == 0
                          ? 'today'
                          : next.daysAway == 1
                          ? 'day'
                          : 'days',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(next.icon, size: 18, color: scheme.primary),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            next.title,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        DateFormat.MMMMEEEEd().format(next.date),
                        if (next.detail != null) next.detail!,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (later.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: 6),
            for (final date in later)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(date.icon, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        date.title,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      date.countdownLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ComingUpSurface extends StatelessWidget {
  const _ComingUpSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(24),
      ),
      child: child,
    );
  }
}
