import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/together/models/calendar_event.dart';

/// Bottom sheet with an event's details. Pops with 'edit' or 'delete'.
class EventDetailsSheet extends StatelessWidget {
  const EventDetailsSheet({
    super.key,
    required this.event,
    required this.when,
    required this.canEdit,
  });

  final CalendarEvent event;
  final DateTime when;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final end = event.end;

    String dateLine() {
      final date = DateFormat.yMMMMEEEEd().format(when);
      if (event.spanDays > 1 && end != null) {
        final last = DateTime(
          when.year,
          when.month,
          when.day + event.spanDays - 1,
        );
        return '$date – ${DateFormat.MMMMd().format(last)}';
      }
      if (event.allDay) return date;
      return '$date · ${DateFormat.jm().format(when)}';
    }

    Widget row(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${event.type.emoji}  '
              '${event.title.isEmpty ? event.type.label : event.title}',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            row(Icons.event_outlined, dateLine()),
            if (event.repeatYearly) row(Icons.repeat, 'Every year'),
            if (event.location != null)
              row(Icons.place_outlined, event.location!),
            if (event.budget != null)
              row(
                Icons.account_balance_wallet_outlined,
                'Budget ${NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(event.budget)}',
              ),
            if (event.reminder != ReminderOption.none)
              row(Icons.notifications_none, event.reminder.label),
            if (event.isPrivate)
              row(Icons.lock_outline, 'Private: only you can see this'),
            if (event.notes.isNotEmpty) row(Icons.notes, event.notes),
            if (event.isAutomatic)
              Text(
                event.isDatePlan
                    ? 'From your date planner. Change it in Together › Plans.'
                    : 'Added automatically from your profiles and dates. '
                          'Change it in the Us tab.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (canEdit) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'delete'),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, 'edit'),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
