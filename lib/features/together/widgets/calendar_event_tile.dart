import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/together/models/calendar_event.dart';

/// One event occurrence in a calendar list.
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
    final parts = <String>[
      if (showDate) DateFormat.MMMEd().format(when),
      if (!event.allDay) DateFormat.jm().format(when),
      if (event.spanDays > 1) '${event.spanDays} days',
      if (event.location != null) event.location!,
    ];

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(event.type.emoji),
      ),
      title: Text(event.title.isEmpty ? event.type.label : event.title),
      subtitle: parts.isEmpty ? null : Text(parts.join(' · ')),
      trailing: event.isPrivate
          ? Tooltip(
              message: 'Only you can see this',
              child: Icon(
                Icons.lock_outline,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : null,
    );
  }
}
