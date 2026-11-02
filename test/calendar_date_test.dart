import 'package:couple_app/core/backend/backend.dart';
import 'package:couple_app/core/backend/memory_backend.dart';
import 'package:couple_app/core/utils/calendar_date.dart';
import 'package:couple_app/features/couple/data/couple_service.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/together/models/calendar_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new values are midnight UTC of the calendar day', () {
    final t = CalendarDate.write(DateTime(1999, 12, 1, 23, 45));
    expect(t.toDate().toUtc(), DateTime.utc(1999, 12, 1));
    expect(CalendarDate.read(t), DateTime(1999, 12, 1));
  });

  test('older values (midnight on the writer\'s phone) read as that day', () {
    // Saved in India: 1 Dec 00:00 IST is 30 Nov 18:30 UTC.
    final india = Timestamp.fromDate(DateTime.utc(1999, 11, 30, 18, 30));
    expect(CalendarDate.read(india), DateTime(1999, 12, 1));
    // Saved in New York: 1 Dec 00:00 EST is 1 Dec 05:00 UTC.
    final newYork = Timestamp.fromDate(DateTime.utc(1999, 12, 1, 5));
    expect(CalendarDate.read(newYork), DateTime(1999, 12, 1));
    // Saved in Auckland (standard time): 1 Dec 00:00 is 30 Nov 12:00 UTC.
    final auckland = Timestamp.fromDate(DateTime.utc(1999, 11, 30, 12));
    expect(CalendarDate.read(auckland), DateTime(1999, 12, 1));
  });

  test('non-timestamps read as null', () {
    expect(CalendarDate.read(null), isNull);
    expect(CalendarDate.read('1999-12-01'), isNull);
    expect(CalendarDate.writeOrNull(null), isNull);
  });

  test('the day you started survives a round trip', () async {
    final db = Db(MemoryBackend());
    await db.doc('users/ann').set({'displayName': 'Ann'});
    final couple = await CoupleService(
      db: db,
    ).createCouple('ann', inviterName: 'Ann', startDate: DateTime(2021, 2, 14));
    final stored = await db.doc('couples/${couple.id}').get();
    expect(
      (stored.data()!['startDate'] as Timestamp).toDate().toUtc(),
      DateTime.utc(2021, 2, 14),
    );
    expect(Couple.fromDoc(stored).startDate, DateTime(2021, 2, 14));
  });

  test('all-day events are days; timed events stay moments', () async {
    final db = Db(MemoryBackend());
    final allDay = CalendarEvent(
      id: 'e1',
      title: 'Trip',
      type: EventType.trip,
      start: DateTime(2026, 12, 24),
      end: DateTime(2026, 12, 26),
      createdBy: 'ann',
    );
    await db.doc('couples/c1/events/e1').set(allDay.toMap());
    final back = CalendarEvent.fromDoc(
      await db.doc('couples/c1/events/e1').get(),
    );
    expect(back.start, DateTime(2026, 12, 24));
    expect(back.end, DateTime(2026, 12, 26));

    final dinner = DateTime(2026, 12, 24, 20, 30);
    final timed = CalendarEvent(
      id: 'e2',
      title: 'Dinner',
      type: EventType.dateNight,
      start: dinner,
      allDay: false,
      createdBy: 'ann',
    );
    await db.doc('couples/c1/events/e2').set(timed.toMap());
    final timedBack = CalendarEvent.fromDoc(
      await db.doc('couples/c1/events/e2').get(),
    );
    expect(timedBack.start, dinner);
  });
}
