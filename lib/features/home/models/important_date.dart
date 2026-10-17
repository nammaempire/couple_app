import 'package:flutter/material.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/together/models/calendar_event.dart';
import 'package:couple_app/features/together/models/love_note.dart';

enum ImportantDateKind { anniversary, birthday, meetup, event, note }

/// One upcoming date worth counting down to on the Home screen.
class ImportantDate {
  final ImportantDateKind kind;
  final String title;

  /// Extra context, e.g. "3rd anniversary" or "turns 28".
  final String? detail;

  /// The next occurrence, at midnight local time.
  final DateTime date;

  /// Whole days from today. Zero means today.
  final int daysAway;

  const ImportantDate({
    required this.kind,
    required this.title,
    required this.date,
    required this.daysAway,
    this.detail,
  });

  IconData get icon => switch (kind) {
    ImportantDateKind.anniversary => Icons.favorite,
    ImportantDateKind.birthday => Icons.cake_outlined,
    ImportantDateKind.meetup => Icons.flight_takeoff,
    ImportantDateKind.event => Icons.event_outlined,
    ImportantDateKind.note => Icons.mail_outline,
  };

  String get countdownLabel {
    if (daysAway == 0) return 'Today';
    if (daysAway == 1) return 'Tomorrow';
    return 'In $daysAway days';
  }

  /// Calendar events and incoming love notes count only within this window,
  /// so a far-off trip does not crowd out this week.
  static const eventHorizonDays = 60;

  /// Builds the list of upcoming dates from what the couple has set, soonest
  /// first. Annual dates repeat; the meetup is a one-off. [events] are the
  /// stored calendar events this user can see; [incomingNotes] are love
  /// notes addressed to them.
  static List<ImportantDate> upcoming({
    required Couple couple,
    required AppUser me,
    AppUser? partner,
    required String partnerName,
    DateTime? now,
    List<CalendarEvent> events = const [],
    List<LoveNote> incomingNotes = const [],
  }) {
    final today = _dateOnly(now ?? DateTime.now());
    final dates = <ImportantDate>[];

    final start = couple.startDate;
    if (start != null) {
      final next = nextAnnual(start, today);
      final years = next.year - start.year;
      if (years > 0) {
        dates.add(
          ImportantDate(
            kind: ImportantDateKind.anniversary,
            title: 'Your anniversary',
            detail: '${ordinal(years)} anniversary',
            date: next,
            daysAway: next.difference(today).inDays,
          ),
        );
      }
    }

    void addBirthday(DateTime? birthday, String title) {
      if (birthday == null) return;
      final next = nextAnnual(birthday, today);
      final age = next.year - birthday.year;
      dates.add(
        ImportantDate(
          kind: ImportantDateKind.birthday,
          title: title,
          detail: age > 0 && age < 120 ? 'turns $age' : null,
          date: next,
          daysAway: next.difference(today).inDays,
        ),
      );
    }

    addBirthday(me.birthday, 'Your birthday');
    addBirthday(partner?.birthday, '$partnerName\'s birthday');

    final meetup = couple.nextMeetup;
    if (meetup != null) {
      final day = _dateOnly(meetup);
      final away = day.difference(today).inDays;
      if (away >= 0) {
        dates.add(
          ImportantDate(
            kind: ImportantDateKind.meetup,
            title: 'Seeing each other',
            date: day,
            daysAway: away,
          ),
        );
      }
    }

    final horizon = today.add(const Duration(days: eventHorizonDays));
    for (final event in events) {
      // Birthdays, the anniversary and the meetup are added above; planned
      // dates from the date planner are listed like events.
      if (event.isAutomatic && !event.isDatePlan) continue;
      final next = event.nextOccurrence(today);
      if (next == null) continue;
      final day = _dateOnly(next);
      if (day.isAfter(horizon)) continue;
      // A multi-day trip already under way counts as today.
      final away = day.difference(today).inDays;
      dates.add(
        ImportantDate(
          kind: ImportantDateKind.event,
          title: event.title.isEmpty ? event.type.label : event.title,
          detail: event.location ?? event.type.label,
          date: day.isBefore(today) ? today : day,
          daysAway: away < 0 ? 0 : away,
        ),
      );
    }

    for (final note in incomingNotes) {
      final day = _dateOnly(note.deliverAt);
      if (!note.deliverAt.isAfter(now ?? DateTime.now()) ||
          day.isAfter(horizon)) {
        continue;
      }
      dates.add(
        ImportantDate(
          kind: ImportantDateKind.note,
          title: 'A love note from $partnerName',
          detail: 'sealed until then',
          date: day,
          daysAway: day.difference(today).inDays,
        ),
      );
    }

    dates.sort((a, b) => a.daysAway.compareTo(b.daysAway));
    return dates;
  }

  /// The next time [original]'s month and day come round, today included.
  /// Feb 29 falls on Feb 28 in non-leap years.
  static DateTime nextAnnual(DateTime original, DateTime today) {
    DateTime inYear(int year) {
      final lastDay = DateTime(year, original.month + 1, 0).day;
      final day = original.day > lastDay ? lastDay : original.day;
      return DateTime(year, original.month, day);
    }

    final thisYear = inYear(today.year);
    return thisYear.isBefore(today) ? inYear(today.year + 1) : thisYear;
  }

  static String ordinal(int n) {
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 13) return '${n}th';
    return switch (n % 10) {
      1 => '${n}st',
      2 => '${n}nd',
      3 => '${n}rd',
      _ => '${n}th',
    };
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
