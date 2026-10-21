import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/plans/widgets/soft_kit.dart';
import 'package:couple_app/features/together/models/calendar_event.dart';
import 'package:couple_app/features/together/widgets/calendar_event_tile.dart';

/// The selected day's events, or a prompt to plan something.
class CalendarDaySection extends StatelessWidget {
  const CalendarDaySection({
    super.key,
    required this.day,
    required this.events,
    required this.onOpen,
    required this.onAdd,
  });

  final DateTime day;
  final List<(CalendarEvent, DateTime)> events;
  final ValueChanged<(CalendarEvent, DateTime)> onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftSectionHeader(label: DateFormat.MMMMEEEEd().format(day)),
        if (events.isEmpty)
          TintedCard(
            muted: true,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Nothing planned.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Plan something'),
                ),
              ],
            ),
          )
        else
          for (final (i, entry) in events.indexed)
            stagger(
              i,
              CalendarEventTile(
                event: entry.$1,
                when: entry.$2,
                showDate: false,
                onTap: () => onOpen(entry),
              ),
            ),
      ],
    );
  }
}
