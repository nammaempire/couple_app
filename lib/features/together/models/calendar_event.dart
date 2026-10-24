import 'package:couple_app/core/backend/backend.dart';
import 'package:flutter/material.dart';

enum EventType {
  dateNight('dateNight', 'Date night', '🍷', Icons.wine_bar_outlined),
  trip('trip', 'Trip', '✈️', Icons.flight_takeoff),
  anniversary('anniversary', 'Anniversary', '💍', Icons.favorite),
  birthday('birthday', 'Birthday', '🎂', Icons.cake_outlined),
  meetup('meetup', 'Meetup', '🫶', Icons.people_outline),
  custom('custom', 'Other', '📌', Icons.event_outlined);

  const EventType(this.id, this.label, this.emoji, this.icon);
  final String id;
  final String label;
  final String emoji;
  final IconData icon;

  static EventType fromId(String? id) {
    for (final t in values) {
      if (t.id == id) return t;
    }
    return EventType.custom;
  }
}

/// When to be reminded before an event.
enum ReminderOption {
  none('none', 'No reminder', null),
  atTime('atTime', 'At the time', Duration.zero),
  hour('hour', '1 hour before', Duration(hours: 1)),
  day('day', '1 day before', Duration(days: 1)),
  week('week', '1 week before', Duration(days: 7));

  const ReminderOption(this.id, this.label, this.before);
  final String id;
  final String label;
  final Duration? before;

  static ReminderOption fromId(String? id) {
    for (final r in values) {
      if (r.id == id) return r;
    }
    return ReminderOption.none;
  }
}

/// Something on the shared calendar.
class CalendarEvent {
  final String id;
  final String title;
  final EventType type;

  /// Start. For all-day events only the date matters.
  final DateTime start;

  /// Optional last day (trips) or end time.
  final DateTime? end;

  final bool allDay;
  final String? location;
  final String notes;

  /// Optional budget in rupees.
  final num? budget;

  /// Repeats every year on the same date (birthdays, anniversaries).
  final bool repeatYearly;

  /// Visible only to [createdBy]. Enforced by the security rules.
  final bool isPrivate;

  final ReminderOption reminder;
  final String createdBy;

  /// Built from other data (birthdays, anniversary, meetup, planned dates)
  /// rather than stored as an event; cannot be edited here.
  final bool isAutomatic;

  /// Id prefix for entries that come from the date planner.
  static const datePlanIdPrefix = 'dateplan-';

  /// A planned date from the date planner, shown here read-only. It keeps
  /// its own reminder, unlike birthdays and the anniversary.
  bool get isDatePlan => isAutomatic && id.startsWith(datePlanIdPrefix);

  /// For yearly events: the first year to show. Defaults to [start]'s year.
  final int? firstYear;

  const CalendarEvent({
    required this.id,
    required this.title,
    required this.type,
    required this.start,
    required this.createdBy,
    this.end,
    this.allDay = true,
    this.location,
    this.notes = '',
    this.budget,
    this.repeatYearly = false,
    this.isPrivate = false,
    this.reminder = ReminderOption.none,
    this.isAutomatic = false,
    this.firstYear,
  });

  factory CalendarEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final location = (data['location'] as String?)?.trim();
    return CalendarEvent(
      id: doc.id,
      title: (data['title'] as String?) ?? '',
      type: EventType.fromId(data['type'] as String?),
      start: (data['start'] as Timestamp?)?.toDate() ?? DateTime.now(),
      end: (data['end'] as Timestamp?)?.toDate(),
      allDay: (data['allDay'] as bool?) ?? true,
      location: (location == null || location.isEmpty) ? null : location,
      notes: (data['notes'] as String?) ?? '',
      budget: data['budget'] as num?,
      repeatYearly: (data['repeatYearly'] as bool?) ?? false,
      isPrivate: (data['private'] as bool?) ?? false,
      reminder: ReminderOption.fromId(data['reminder'] as String?),
      createdBy: (data['createdBy'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    final trimmedLocation = location?.trim();
    return {
      'title': title.trim(),
      'type': type.id,
      'start': Timestamp.fromDate(start),
      'end': end == null ? null : Timestamp.fromDate(end!),
      'allDay': allDay,
      'location': (trimmedLocation == null || trimmedLocation.isEmpty)
          ? null
          : trimmedLocation,
      'notes': notes.trim(),
      'budget': budget,
      'repeatYearly': repeatYearly,
      'private': isPrivate,
      'reminder': reminder.id,
      'createdBy': createdBy,
    };
  }

  /// Whole days the event spans (1 for a single-day event).
  int get spanDays {
    final e = end;
    if (e == null) return 1;
    final a = DateTime(start.year, start.month, start.day);
    final b = DateTime(e.year, e.month, e.day);
    final days = b.difference(a).inDays + 1;
    return days < 1 ? 1 : days;
  }

  /// Start times of every occurrence overlapping [from]..[to] (inclusive
  /// dates). Yearly events repeat; Feb 29 falls on Feb 28 in other years.
  List<DateTime> occurrencesBetween(DateTime from, DateTime to) {
    final first = DateTime(from.year, from.month, from.day);
    final last = DateTime(to.year, to.month, to.day);
    final span = spanDays;

    bool overlaps(DateTime occurrenceStart) {
      final day = DateTime(
        occurrenceStart.year,
        occurrenceStart.month,
        occurrenceStart.day,
      );
      final lastDay = DateTime(day.year, day.month, day.day + span - 1);
      return !lastDay.isBefore(first) && !day.isAfter(last);
    }

    if (!repeatYearly) return overlaps(start) ? [start] : const [];

    final result = <DateTime>[];
    for (var year = first.year - 1; year <= last.year; year++) {
      if (year < (firstYear ?? start.year)) continue;
      final lastOfMonth = DateTime(year, start.month + 1, 0).day;
      final day = start.day > lastOfMonth ? lastOfMonth : start.day;
      final occurrence = DateTime(
        year,
        start.month,
        day,
        start.hour,
        start.minute,
      );
      if (overlaps(occurrence)) result.add(occurrence);
    }
    return result;
  }

  /// True if the event (any occurrence) covers [day].
  bool occursOn(DateTime day) => occurrencesBetween(day, day).isNotEmpty;

  /// The next occurrence starting today or later, if any.
  DateTime? nextOccurrence(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final hits = occurrencesBetween(today, DateTime(today.year + 1, 12, 31));
    for (final h in hits) {
      final day = DateTime(h.year, h.month, h.day);
      final lastDay = DateTime(day.year, day.month, day.day + spanDays - 1);
      if (!lastDay.isBefore(today)) return h;
    }
    return null;
  }
}
