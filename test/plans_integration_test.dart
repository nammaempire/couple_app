import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/home/models/important_date.dart';
import 'package:couple_app/features/plans/models/date_plan.dart';
import 'package:couple_app/features/together/data/reminder_planner.dart';
import 'package:couple_app/features/together/models/calendar_event.dart';

/// How planned dates from the date planner flow into the calendar,
/// reminders and Home's "Coming up".
void main() {
  // Thursday morning; the date is Saturday evening.
  final now = DateTime(2026, 10, 15, 9);
  final saturday = DateTime(2026, 10, 17, 19, 30);

  const me = AppUser(uid: 'me', displayName: 'Asha', coupleId: 'c1');
  const couple = Couple(id: 'c1', inviteCode: 'ABC234', memberIds: ['me', 'p']);

  DatePlan plan(DatePlanStatus status) => DatePlan(
    id: 'p1',
    title: 'Sunset picnic',
    createdBy: 'me',
    status: status,
    scheduledAt: saturday,
    location: 'Cubbon Park',
  );

  group('calendar entry', () {
    test('a planned date is a read-only date-plan entry', () {
      final event = plan(DatePlanStatus.planned).toCalendarEvent()!;
      expect(event.isAutomatic, isTrue);
      expect(event.isDatePlan, isTrue);
      expect(event.reminder, ReminderOption.hour);
      expect(event.start, saturday);
    });

    test('ideas have no calendar entry; done dates have no reminder', () {
      expect(plan(DatePlanStatus.idea).toCalendarEvent(), isNull);
      final done = plan(DatePlanStatus.done).toCalendarEvent()!;
      expect(done.reminder, ReminderOption.none);
    });

    test('birthdays are automatic but not date plans', () {
      final birthday = CalendarEvent(
        id: 'auto-birthday-me',
        title: 'Your birthday',
        type: EventType.birthday,
        start: DateTime(1995, 3, 2),
        repeatYearly: true,
        createdBy: '',
        isAutomatic: true,
      );
      expect(birthday.isDatePlan, isFalse);
    });
  });

  group('reminders', () {
    List<PlannedReminder> remindersFor(DatePlan p) => ReminderPlanner.plan(
      now: now,
      events: [p.toCalendarEvent()!],
      incomingNotes: const [],
      prefs: const NotificationPrefs(),
      partnerName: 'Ravi',
    );

    test('a planned date gets one reminder an hour before', () {
      final reminders = remindersFor(plan(DatePlanStatus.planned));
      expect(reminders, hasLength(1));
      expect(reminders.single.at, saturday.subtract(const Duration(hours: 1)));
    });

    test('a planned date never gets anniversary wording', () {
      final reminders = remindersFor(plan(DatePlanStatus.planned));
      for (final r in reminders) {
        expect(r.body, isNot(contains('anniversary')));
        expect(r.body, isNot(contains('year together')));
      }
    });

    test('a date already marked done gets no reminder', () {
      expect(remindersFor(plan(DatePlanStatus.done)), isEmpty);
    });
  });

  group('Coming up on Home', () {
    test('lists a planned date', () {
      final dates = ImportantDate.upcoming(
        couple: couple,
        me: me,
        partnerName: 'Ravi',
        now: now,
        events: [plan(DatePlanStatus.planned).toCalendarEvent()!],
      );
      expect(dates.map((d) => d.title), contains('Sunset picnic'));
    });
  });
}
