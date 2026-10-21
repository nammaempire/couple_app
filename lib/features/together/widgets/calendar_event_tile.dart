import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/plans/widgets/soft_kit.dart';
import 'package:couple_app/features/together/models/calendar_event.dart';
import 'package:couple_app/features/together/widgets/calendar_event_look.dart';

/// One event occurrence in a calendar list: a soft card tinted by the kind
/// of event.
class CalendarEventTile extends StatelessWidget {
  const CalendarEventTile({
    super.key,
    required this.event,
    required this.when,
    required this.showDate,
    required this.onTap,
  });

  final CalendarEvent event;
  final DateTime when;
  final bool showDate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preset = event.type.preset;
    final parts = <String>[
      if (showDate) DateFormat.MMMEd().format(when),
      if (!event.allDay) DateFormat.jm().format(when),
      if (event.spanDays > 1) '${event.spanDays} days',
      if (event.location != null) event.location!,
    ];

    return TintedCard(
      preset: preset,
      onTap: onTap,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      child: Row(
        children: [
          EmojiBadge(emoji: event.type.emoji, preset: preset, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title.isEmpty ? event.type.label : event.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (parts.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    parts.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (event.isPrivate)
            Tooltip(
              message: 'Only you can see this',
              child: Icon(
                Icons.lock_outline,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
