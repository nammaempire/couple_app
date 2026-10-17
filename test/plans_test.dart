import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/home/models/important_date.dart';
import 'package:couple_app/features/memories/models/memory.dart';
import 'package:couple_app/features/together/data/event_service.dart';
import 'package:couple_app/features/together/data/reminder_planner.dart';
import 'package:couple_app/features/together/models/calendar_event.dart';
import 'package:couple_app/features/together/models/love_note.dart';

CalendarEvent event({
  String id = 'e1',
  String title = 'Dinner',
  EventType type = EventType.dateNight,
  required DateTime start,
  DateTime? end,
  bool allDay = true,
  bool repeatYearly = false,
  ReminderOption reminder = ReminderOption.none,
  bool automatic = false,
}) => CalendarEvent(
  id: id,
  title: title,
  type: type,
  start: start,
  end: end,
  allDay: allDay,
  repeatYearly: repeatYearly,
  reminder: reminder,
  createdBy: 'u1',
  isAutomatic: automatic,
);

void main() {
  group('CalendarEvent occurrences', () {
    test('a one-off event occurs only on its day', () {
      final e = event(start: DateTime(2026, 10, 3, 19, 30), allDay: false);
      expect(e.occursOn(DateTime(2026, 10, 3)), isTrue);
      expect(e.occursOn(DateTime(2026, 10, 4)), isFalse);
      expect(e.occursOn(DateTime(2027, 10, 3)), isFalse);
    });

    test('yearly events repeat, never before the first year', () {
      final e = event(start: DateTime(2024, 5, 20), repeatYearly: true);
      expect(e.occursOn(DateTime(2026, 5, 20)), isTrue);
      expect(e.occursOn(DateTime(2023, 5, 20)), isFalse);
    });

    test('Feb 29 repeats on Feb 28 in other years', () {
      final e = event(start: DateTime(2024, 2, 29), repeatYearly: true);
      expect(e.occursOn(DateTime(2027, 2, 28)), isTrue);
      expect(e.occursOn(DateTime(2028, 2, 29)), isTrue);
    });

    test('a trip covers every day from start to end', () {
      final trip = event(
        type: EventType.trip,
        start: DateTime(2026, 12, 30),
        end: DateTime(2027, 1, 2),
      );
      expect(trip.spanDays, 4);
      expect(trip.occursOn(DateTime(2026, 12, 29)), isFalse);
      expect(trip.occursOn(DateTime(2026, 12, 31)), isTrue);
      expect(trip.occursOn(DateTime(2027, 1, 2)), isTrue);
      expect(trip.occursOn(DateTime(2027, 1, 3)), isFalse);
      // Already under way counts as the next occurrence.
      expect(trip.nextOccurrence(DateTime(2027, 1, 1)), DateTime(2026, 12, 30));
    });

    test('round-trips through Firestore fields', () {
      final e = event(
        start: DateTime(2026, 10, 3, 19, 30),
        allDay: false,
        reminder: ReminderOption.hour,
      );
      final map = e.toMap();
      expect(map['type'], 'dateNight');
      expect(map['private'], isFalse);
      expect(map['reminder'], 'hour');
      expect(EventType.fromId('nonsense'), EventType.custom);
      expect(ReminderOption.fromId(null), ReminderOption.none);
    });
  });

  group('Automatic calendar dates', () {
    test('anniversary starts from the first one; birthdays and meetup', () {
      final couple = Couple(
        id: 'c',
        inviteCode: 'X',
        memberIds: const ['u1', 'u2'],
        startDate: DateTime(2023, 2, 14),
        nextMeetup: DateTime(2026, 10, 10),
      );
      final list = EventService.automaticEvents(
        couple: couple,
        me: AppUser(
          uid: 'u1',
          displayName: 'N',
          birthday: DateTime(1996, 7, 1),
        ),
        partner: AppUser(
          uid: 'u2',
          displayName: 'P',
          birthday: DateTime(1998, 1, 9),
        ),
        partnerName: 'Priya',
      );
      expect(list.map((e) => e.title), [
        'Our anniversary',
        'Your birthday',
        'Priya\'s birthday',
        'Seeing each other',
      ]);
      final anniversary = list.first;
      expect(anniversary.occursOn(DateTime(2023, 2, 14)), isFalse);
      expect(anniversary.occursOn(DateTime(2024, 2, 14)), isTrue);
      expect(list.every((e) => e.isAutomatic), isTrue);
    });

    test('a Feb 29 start date: 28th in ordinary years, 29th in leap years', () {
      final couple = Couple(
        id: 'c',
        inviteCode: 'X',
        memberIds: const ['u1', 'u2'],
        startDate: DateTime(2024, 2, 29),
      );
      final anniversary = EventService.automaticEvents(
        couple: couple,
        me: const AppUser(uid: 'u1', displayName: 'N'),
        partner: null,
        partnerName: 'P',
      ).single;
      expect(anniversary.occursOn(DateTime(2024, 2, 29)), isFalse);
      expect(anniversary.occursOn(DateTime(2025, 2, 28)), isTrue);
      expect(anniversary.occursOn(DateTime(2025, 3, 1)), isFalse);
      expect(anniversary.occursOn(DateTime(2028, 2, 29)), isTrue);
    });
  });

  group('ReminderPlanner', () {
    final now = DateTime(2026, 9, 27, 12);
    const prefs = NotificationPrefs();

    test('schedules a chosen reminder before the event', () {
      final plan = ReminderPlanner.plan(
        now: now,
        events: [
          event(
            start: DateTime(2026, 10, 3, 19, 30),
            allDay: false,
            reminder: ReminderOption.hour,
          ),
        ],
        incomingNotes: const [],
        prefs: prefs,
        partnerName: 'Priya',
      );
      expect(plan.single.at, DateTime(2026, 10, 3, 18, 30));
      expect(plan.single.body, 'In one hour');
    });

    test('all-day events remind at 9am; past reminders are dropped', () {
      final plan = ReminderPlanner.plan(
        now: now,
        events: [
          event(start: DateTime(2026, 10, 1), reminder: ReminderOption.day),
          // Reminder would have been yesterday.
          event(
            id: 'e2',
            start: DateTime(2026, 9, 28, 9),
            reminder: ReminderOption.week,
          ),
        ],
        incomingNotes: const [],
        prefs: prefs,
        partnerName: 'Priya',
      );
      expect(plan.single.at, DateTime(2026, 9, 30, 9));
    });

    test('birthdays get a day-before and on-the-day reminder', () {
      final plan = ReminderPlanner.plan(
        now: now,
        events: [
          event(
            id: 'auto-birthday-partner',
            title: 'Priya\'s birthday',
            type: EventType.birthday,
            start: DateTime(1998, 10, 9),
            repeatYearly: true,
            automatic: true,
          ),
        ],
        incomingNotes: const [],
        prefs: prefs,
        partnerName: 'Priya',
      );
      expect(plan.map((r) => r.at), [
        DateTime(2026, 10, 8, 9),
        DateTime(2026, 10, 9, 9),
      ]);
    });

    test('quiet hours move late reminders to the evening before 22:00', () {
      final late = event(
        start: DateTime(2026, 10, 3, 23, 0),
        allDay: false,
        reminder: ReminderOption.atTime,
      );
      final early = event(
        id: 'e2',
        start: DateTime(2026, 10, 5, 6, 0),
        allDay: false,
        reminder: ReminderOption.atTime,
      );
      final plan = ReminderPlanner.plan(
        now: now,
        events: [late, early],
        incomingNotes: const [],
        prefs: prefs.copyWith(quietHours: true),
        partnerName: 'Priya',
      );
      expect(plan.map((r) => r.at), [
        DateTime(2026, 10, 3, 21, 30),
        DateTime(2026, 10, 4, 21, 30),
      ]);
    });

    test('turning off date notifications removes event reminders', () {
      final plan = ReminderPlanner.plan(
        now: now,
        events: [
          event(start: DateTime(2026, 10, 1), reminder: ReminderOption.day),
        ],
        incomingNotes: const [],
        prefs: prefs.copyWith(dates: false),
        partnerName: 'Priya',
      );
      expect(plan, isEmpty);
    });

    test('a scheduled love note alerts at delivery time', () {
      final note = LoveNote(
        id: 'n1',
        senderId: 'u2',
        recipientId: 'u1',
        kind: NoteKind.letter,
        title: '',
        deliverAt: DateTime(2026, 10, 1, 8),
      );
      final plan = ReminderPlanner.plan(
        now: now,
        events: const [],
        incomingNotes: [note],
        prefs: prefs,
        partnerName: 'Priya',
      );
      expect(plan.single.at, DateTime(2026, 10, 1, 8));
      expect(plan.single.title, '💌 A love note from Priya');
    });

    test('ids are stable across runs', () {
      final r = PlannedReminder(
        key: 'event:e1:2026-10-3',
        at: DateTime(2026),
        title: '',
        body: '',
      );
      expect(
        r.id,
        PlannedReminder(
          key: r.key,
          at: DateTime(2027),
          title: 'x',
          body: 'y',
        ).id,
      );
      expect(r.id, greaterThanOrEqualTo(0));
    });
  });

  group('Memories', () {
    Memory memory(
      String id,
      DateTime date, {
      String album = MemoryAlbums.trips,
      String? place,
      bool favorite = false,
      int photos = 1,
    }) => Memory(
      id: id,
      title: 'Memory $id',
      caption: 'lovely day',
      date: date,
      album: album,
      place: place,
      favorite: favorite,
      createdBy: 'u1',
      media: [
        for (var i = 0; i < photos; i++)
          MemoryMedia(type: MemoryMediaType.image, url: '$id-$i.jpg'),
      ],
    );

    test('search matches title, caption, place and album', () {
      final m = memory('1', DateTime(2026, 1, 1), place: 'Coorg');
      expect(m.matches('coorg'), isTrue);
      expect(m.matches('LOVELY'), isTrue);
      expect(m.matches('trips'), isTrue);
      expect(m.matches('goa'), isFalse);
    });

    test('custom albums follow the defaults', () {
      final albums = MemoryAlbums.all([
        memory('1', DateTime(2026), album: 'Zoo day'),
        memory('2', DateTime(2026), album: 'Anniversaries'),
        memory('3', DateTime(2026), album: 'Beach'),
      ]);
      expect(albums.take(5), MemoryAlbums.defaults);
      expect(albums.skip(5), ['Beach', 'Zoo day']);
    });

    test('monthly recap counts, places and favourites-first highlights', () {
      final all = [
        memory('a', DateTime(2026, 9, 2), place: 'Coorg', photos: 2),
        memory('b', DateTime(2026, 9, 20), place: 'Coorg', favorite: true),
        memory(
          'c',
          DateTime(2026, 9, 25),
          place: 'Mysore',
          album: MemoryAlbums.randomMoments,
        ),
        memory('d', DateTime(2026, 8, 25)),
      ];
      final recap = MemoryRecap.month(all, 2026, 9);
      expect(recap.label, 'September 2026');
      expect(recap.memories.length, 3);
      expect(recap.photoCount, 4);
      expect(recap.places, ['Coorg', 'Mysore']);
      expect(recap.topAlbum, MemoryAlbums.trips);
      expect(recap.highlights(2), ['b-0.jpg', 'a-0.jpg']);
      expect(MemoryRecap.year(all, 2026).memories.length, 4);
    });

    test('on this day finds earlier years only', () {
      final all = [
        memory('old', DateTime(2024, 9, 27)),
        memory('today', DateTime(2026, 9, 27)),
        memory('other', DateTime(2025, 9, 26)),
      ];
      expect(
        MemoryRecap.onThisDay(all, DateTime(2026, 9, 27)).map((m) => m.id),
        ['old'],
      );
    });
  });

  group('Love notes and Coming up', () {
    final today = DateTime(2026, 9, 27, 10);

    test('note states', () {
      final note = LoveNote(
        id: 'n',
        senderId: 'a',
        recipientId: 'b',
        kind: NoteKind.openWhen,
        openWhen: OpenWhen.badDay,
        title: '',
        deliverAt: DateTime(2026, 9, 28),
      );
      expect(note.isScheduled(today), isTrue);
      expect(note.isDelivered(DateTime(2026, 9, 28)), isTrue);
      expect(note.envelopeTitle, 'Open when you\'re having a bad day');
      expect(OpenWhen.fromId('nope'), isNull);
    });

    test('Coming up includes events within 60 days and sealed notes', () {
      final couple = Couple(
        id: 'c',
        inviteCode: 'X',
        memberIds: const ['u1', 'u2'],
      );
      final dates = ImportantDate.upcoming(
        couple: couple,
        me: const AppUser(uid: 'u1', displayName: 'N'),
        partnerName: 'Priya',
        now: today,
        events: [
          event(
            title: 'Coorg trip',
            type: EventType.trip,
            start: DateTime(2026, 10, 10),
          ),
          event(id: 'far', title: 'Far away', start: DateTime(2027, 3, 1)),
          event(
            id: 'auto',
            title: 'Auto',
            start: DateTime(2026, 10, 1),
            automatic: true,
          ),
        ],
        incomingNotes: [
          LoveNote(
            id: 'n',
            senderId: 'u2',
            recipientId: 'u1',
            kind: NoteKind.letter,
            title: '',
            deliverAt: DateTime(2026, 9, 30, 8),
          ),
        ],
      );
      expect(dates.map((d) => d.title), [
        'A love note from Priya',
        'Coorg trip',
      ]);
      expect(dates.first.daysAway, 3);
    });
  });
}
