import 'package:flutter/foundation.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/together/models/calendar_event.dart';
import 'package:couple_app/features/together/models/love_note.dart';

/// One notification to fire at [at] on this device.
@immutable
class PlannedReminder {
  const PlannedReminder({
    required this.key,
    required this.at,
    required this.title,
    required this.body,
  });

  /// Stable identity, so re-planning produces the same notification id.
  final String key;
  final DateTime at;
  final String title;
  final String body;

  /// Positive 31-bit id derived from [key] (FNV-1a, stable across runs,
  /// unlike String.hashCode).
  int get id {
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  @override
  String toString() => 'PlannedReminder($key @ $at: $title — $body)';
}

/// Works out which reminders this device should have scheduled. Pure, so it
/// can be tested without a phone.
class ReminderPlanner {
  const ReminderPlanner._();

  /// How far ahead to schedule. Re-planned every time the app opens.
  static const horizon = Duration(days: 60);

  /// Android caps pending alarms per app; stay well under.
  static const maxReminders = 40;

  /// All-day events are reminded at this hour.
  static const allDayHour = 9;

  static List<PlannedReminder> plan({
    required DateTime now,
    required List<CalendarEvent> events,
    required List<LoveNote> incomingNotes,
    required NotificationPrefs prefs,
    required String partnerName,
  }) {
    final result = <PlannedReminder>[];
    final until = now.add(horizon);

    if (prefs.dates) {
      for (final event in events) {
        for (final occurrence in event.occurrencesBetween(now, until)) {
          result.addAll(_forOccurrence(event, occurrence));
        }
      }
    }

    if (prefs.messages) {
      for (final note in incomingNotes) {
        if (!note.deliverAt.isAfter(now) || note.deliverAt.isAfter(until)) {
          continue;
        }
        result.add(
          PlannedReminder(
            key: 'note:${note.id}',
            at: note.deliverAt,
            title: '💌 A love note from $partnerName',
            body: note.kind == NoteKind.openWhen
                ? 'It\'s ready to open.'
                : 'It just arrived. Open it whenever you like.',
          ),
        );
      }
    }

    final adjusted =
        result
            .map((r) => prefs.quietHours ? _outsideQuietHours(r) : r)
            .where((r) => r.at.isAfter(now))
            .toList()
          ..sort((a, b) => a.at.compareTo(b.at));

    // Two reminders can land on the same key (e.g. duplicated events); keep
    // the first.
    final seen = <int>{};
    final unique = adjusted.where((r) => seen.add(r.id)).toList();
    return unique.take(maxReminders).toList();
  }

  static List<PlannedReminder> _forOccurrence(
    CalendarEvent event,
    DateTime occurrence,
  ) {
    final day = DateTime(occurrence.year, occurrence.month, occurrence.day);
    final start = event.allDay
        ? DateTime(day.year, day.month, day.day, allDayHour)
        : occurrence;
    final dateKey = '${day.year}-${day.month}-${day.day}';
    final emoji = event.type.emoji;

    // Birthdays and the anniversary always get a heads-up the day before
    // and on the day; other events (meetups and planned dates included) use
    // their chosen reminder.
    if (event.isAutomatic &&
        !event.isDatePlan &&
        event.type != EventType.meetup) {
      return [
        PlannedReminder(
          key: 'auto:${event.id}:$dateKey:before',
          at: start.subtract(const Duration(days: 1)),
          title: '$emoji Tomorrow: ${event.title}',
          body: event.type == EventType.birthday
              ? 'A good moment to plan something small.'
              : 'Another year together tomorrow.',
        ),
        PlannedReminder(
          key: 'auto:${event.id}:$dateKey:day',
          at: start,
          title: '$emoji Today: ${event.title}',
          body: event.type == EventType.birthday
              ? 'Don\'t forget to celebrate!'
              : 'Happy anniversary 💞',
        ),
      ];
    }

    final before = event.reminder.before;
    if (before == null) return const [];
    return [
      PlannedReminder(
        key: 'event:${event.id}:$dateKey',
        at: start.subtract(before),
        title: '$emoji ${event.title}',
        body: _whenLabel(event, start, before),
      ),
    ];
  }

  static String _whenLabel(
    CalendarEvent event,
    DateTime start,
    Duration before,
  ) {
    final place = event.location == null ? '' : ' · ${event.location}';
    if (before == Duration.zero) {
      return event.allDay ? 'Today$place' : 'Starting now$place';
    }
    if (before.inDays >= 7) return 'In one week$place';
    if (before.inDays >= 1) return 'Tomorrow$place';
    return 'In one hour$place';
  }

  /// Moves a reminder that falls in quiet hours (22:00–07:00) to 21:30 the
  /// evening before, so it still arrives ahead of the event.
  static PlannedReminder _outsideQuietHours(PlannedReminder r) {
    final hour = r.at.hour;
    if (hour >= 7 && hour < 22) return r;
    final evening = hour >= 22
        ? DateTime(r.at.year, r.at.month, r.at.day, 21, 30)
        : DateTime(r.at.year, r.at.month, r.at.day - 1, 21, 30);
    return PlannedReminder(
      key: r.key,
      at: evening,
      title: r.title,
      body: r.body,
    );
  }
}
