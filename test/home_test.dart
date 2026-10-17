import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/home/models/daily_question.dart';
import 'package:couple_app/features/home/models/important_date.dart';
import 'package:couple_app/features/home/models/love_tap.dart';

void main() {
  group('Couple.calendarDifference', () {
    test('whole years, months and days', () {
      final d = Couple.calendarDifference(
        DateTime(2022, 3, 10),
        DateTime(2024, 6, 15),
      );
      expect((d.years, d.months, d.days), (2, 3, 5));
    });

    test('borrows the right number of days across a short month', () {
      // Jan 31 → Mar 1 (2023, not a leap year): 1 month and 1 day.
      final d = Couple.calendarDifference(
        DateTime(2023, 1, 31),
        DateTime(2023, 3, 1),
      );
      expect((d.years, d.months, d.days), (0, 1, 1));
    });

    test('same day is zero', () {
      final d = Couple.calendarDifference(
        DateTime(2024, 5, 5, 23),
        DateTime(2024, 5, 5, 1),
      );
      expect((d.years, d.months, d.days), (0, 0, 0));
    });
  });

  group('ImportantDate', () {
    final today = DateTime(2026, 9, 27);
    const me = AppUser(uid: 'u1', displayName: 'Navi');

    test('nextAnnual rolls to next year once passed, includes today', () {
      expect(
        ImportantDate.nextAnnual(DateTime(1998, 9, 27), today),
        DateTime(2026, 9, 27),
      );
      expect(
        ImportantDate.nextAnnual(DateTime(1998, 9, 26), today),
        DateTime(2027, 9, 26),
      );
    });

    test('Feb 29 falls on Feb 28 in non-leap years', () {
      expect(
        ImportantDate.nextAnnual(DateTime(2000, 2, 29), today),
        DateTime(2027, 2, 28),
      );
      expect(
        ImportantDate.nextAnnual(DateTime(2000, 2, 29), DateTime(2028, 1, 1)),
        DateTime(2028, 2, 29),
      );
    });

    test('ordinals', () {
      expect(
        [1, 2, 3, 4, 11, 12, 13, 21, 22, 101, 111].map(ImportantDate.ordinal),
        [
          '1st',
          '2nd',
          '3rd',
          '4th',
          '11th',
          '12th',
          '13th',
          '21st',
          '22nd',
          '101st',
          '111th',
        ],
      );
    });

    test('upcoming lists every set date, soonest first', () {
      final couple = Couple(
        id: 'c1',
        inviteCode: 'ABC234',
        memberIds: const ['u1', 'u2'],
        startDate: DateTime(2023, 10, 5),
        nextMeetup: DateTime(2026, 10, 1),
      );
      final partner = AppUser(
        uid: 'u2',
        displayName: 'Priya',
        birthday: DateTime(1999, 12, 1),
      );
      final dates = ImportantDate.upcoming(
        couple: couple,
        me: me.copyWith(),
        partner: partner,
        partnerName: 'Priya',
        now: today,
      );

      expect(dates.map((d) => d.title), [
        'Seeing each other',
        'Your anniversary',
        'Priya\'s birthday',
      ]);
      expect(dates[0].daysAway, 4);
      expect(dates[1].detail, '3rd anniversary');
      expect(dates[2].detail, 'turns 27');
    });

    test('a past meetup and a first-year anniversary are left out', () {
      final couple = Couple(
        id: 'c1',
        inviteCode: 'ABC234',
        memberIds: const ['u1', 'u2'],
        startDate: DateTime(2026, 9, 1),
        nextMeetup: DateTime(2026, 9, 1),
      );
      final dates = ImportantDate.upcoming(
        couple: couple,
        me: me,
        partnerName: 'Priya',
        now: today,
      );
      // Anniversary lands 2027-09-01 as the 1st, which is kept; meetup gone.
      expect(dates.map((d) => d.title), ['Your anniversary']);
      expect(dates.single.detail, '1st anniversary');
    });
  });

  group('QuestionBank.streak', () {
    final today = DateTime(2026, 3, 2);
    String key(int month, int day) =>
        QuestionBank.dateKeyFor(DateTime(2026, month, day));

    test('counts back from today across a month boundary', () {
      expect(
        QuestionBank.streak([
          key(3, 2),
          key(3, 1),
          key(2, 28),
          key(2, 27),
        ], today),
        4,
      );
    });

    test('still counts from yesterday before today is answered', () {
      expect(QuestionBank.streak([key(3, 1), key(2, 28)], today), 2);
    });

    test('a gap ends the streak', () {
      expect(QuestionBank.streak([key(3, 2), key(2, 28)], today), 1);
      expect(QuestionBank.streak([key(2, 27)], today), 0);
      expect(QuestionBank.streak(const [], today), 0);
    });
  });

  test('LoveTap falls back to "thinking" for older nudges', () {
    expect(LoveTap.fromId(null), LoveTap.thinking);
    expect(LoveTap.fromId('hug'), LoveTap.hug);
  });
}
