import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/plans/data/date_plan_service.dart';
import 'package:couple_app/features/plans/models/date_plan.dart';
import 'package:couple_app/features/plans/models/date_plan_lists.dart';
import 'package:couple_app/features/plans/providers/date_plan_providers.dart';
import 'package:couple_app/features/plans/screens/date_planner_screen.dart';
import 'package:couple_app/features/together/models/calendar_event.dart';

DatePlan plan(
  String id, {
  DatePlanStatus status = DatePlanStatus.idea,
  DateTime? scheduledAt,
  DateTime? createdAt,
  DateTime? completedAt,
  String location = '',
}) => DatePlan(
  id: id,
  title: 'Plan $id',
  createdBy: 'u1',
  status: status,
  scheduledAt: scheduledAt,
  createdAt: createdAt,
  completedAt: completedAt,
  location: location,
);

/// A Random whose nextInt always returns the given values in turn.
class _FixedRandom implements Random {
  _FixedRandom(this.values);
  final List<int> values;
  int _i = 0;
  final List<int> maxes = [];

  @override
  int nextInt(int max) {
    maxes.add(max);
    return values[_i++ % values.length] % max;
  }

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

/// Records calls instead of touching Firestore.
class _FakeDatePlanService implements DatePlanService {
  final calls = <String>[];

  @override
  Future<void> markDone(
    String coupleId,
    String planId, {
    int? rating,
    String reflection = '',
  }) async => calls.add('markDone $planId $rating "$reflection"');

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  group('DatePlan fields', () {
    test('round-trips through toMap / fromMap', () {
      final original = DatePlan(
        id: 'p1',
        title: '  Sunset picnic  ',
        notes: 'Bring the blanket',
        status: DatePlanStatus.done,
        scheduledAt: DateTime(2026, 10, 18, 19, 30),
        location: 'Cubbon Park',
        estimatedCostMinor: 125050,
        vibe: DateVibe.outdoors,
        rating: 5,
        reflection: 'Perfect evening',
        createdBy: 'u1',
        completedAt: DateTime(2026, 10, 19, 9),
      );
      final map = original.toMap();
      expect(map['title'], 'Sunset picnic');
      expect(map['status'], 'done');
      expect(map['vibe'], 'outdoors');
      expect(map['scheduledAt'], isA<Timestamp>());
      expect(map.containsKey('createdAt'), isFalse);
      expect(map.containsKey('updatedAt'), isFalse);

      final back = DatePlan.fromMap('p1', map);
      expect(back.title, 'Sunset picnic');
      expect(back.notes, 'Bring the blanket');
      expect(back.status, DatePlanStatus.done);
      expect(back.scheduledAt, DateTime(2026, 10, 18, 19, 30));
      expect(back.location, 'Cubbon Park');
      expect(back.estimatedCostMinor, 125050);
      expect(back.vibe, DateVibe.outdoors);
      expect(back.rating, 5);
      expect(back.reflection, 'Perfect evening');
      expect(back.createdBy, 'u1');
      expect(back.completedAt, DateTime(2026, 10, 19, 9));
    });

    test('an empty or malformed document never crashes', () {
      final empty = DatePlan.fromMap('x', const {});
      expect(empty.title, '');
      expect(empty.status, DatePlanStatus.idea);
      expect(empty.vibe, DateVibe.cozy);
      expect(empty.scheduledAt, isNull);
      expect(empty.estimatedCostMinor, isNull);

      final junk = DatePlan.fromMap('y', {
        'title': 42,
        'status': 'archived',
        'vibe': ['fancy'],
        'scheduledAt': 'tomorrow',
        'estimatedCostMinor': -5,
        'rating': 9,
        'reflection': null,
      });
      expect(junk.title, '');
      expect(junk.status, DatePlanStatus.idea);
      expect(junk.vibe, DateVibe.cozy);
      expect(junk.scheduledAt, isNull);
      expect(junk.estimatedCostMinor, isNull);
      expect(junk.rating, isNull);
      expect(junk.reflection, '');
    });

    test('a planned doc without a date falls back to an idea', () {
      final p = DatePlan.fromMap('z', {'title': 'x', 'status': 'planned'});
      expect(p.status, DatePlanStatus.idea);
    });

    test('ratings and costs from doubles are rounded and checked', () {
      final p = DatePlan.fromMap('d', {
        'rating': 4.0,
        'estimatedCostMinor': 9900.0,
      });
      expect(p.rating, 4);
      expect(p.estimatedCostMinor, 9900);
    });

    test('long text is clipped to the schema limits', () {
      final map = DatePlan(
        id: '',
        title: 'a' * 300,
        location: 'b' * 300,
        createdBy: 'u1',
      ).toMap();
      expect((map['title'] as String).length, DatePlan.maxTitle);
      expect((map['location'] as String).length, DatePlan.maxLocation);
    });

    test('enum fromId falls back safely', () {
      expect(DatePlanStatus.fromId(null), DatePlanStatus.idea);
      expect(DatePlanStatus.fromId('done'), DatePlanStatus.done);
      expect(DateVibe.fromId('nope'), DateVibe.cozy);
      expect(DateVibe.fromId('culture'), DateVibe.culture);
      for (final v in DateVibe.values) {
        expect(DateVibe.fromId(v.id), v);
      }
    });

    test('copyWith can clear nullable fields', () {
      final p = plan(
        'p',
        status: DatePlanStatus.planned,
        scheduledAt: DateTime(2026, 11, 1, 20),
      ).copyWith(status: DatePlanStatus.idea, scheduledAt: () => null);
      expect(p.status, DatePlanStatus.idea);
      expect(p.scheduledAt, isNull);
      expect(p.title, 'Plan p');
    });
  });

  group('toCalendarEvent', () {
    test('a planned date becomes an automatic date-night event', () {
      final e = DatePlan(
        id: 'abc',
        title: 'Dinner at Toit',
        notes: 'Window table',
        status: DatePlanStatus.planned,
        scheduledAt: DateTime(2026, 10, 24, 20),
        location: 'Indiranagar',
        createdBy: 'u2',
      ).toCalendarEvent()!;
      expect(e.id, 'dateplan-abc');
      expect(e.type, EventType.dateNight);
      expect(e.title, 'Dinner at Toit');
      expect(e.start, DateTime(2026, 10, 24, 20));
      expect(e.allDay, isFalse);
      expect(e.isAutomatic, isTrue);
      expect(e.createdBy, 'u2');
      expect(e.location, 'Indiranagar');
      expect(e.notes, 'Window table');
      expect(e.occursOn(DateTime(2026, 10, 24)), isTrue);
    });

    test('ideas have no calendar event; empty location becomes null', () {
      expect(plan('i').toCalendarEvent(), isNull);
      final done = plan(
        'd',
        status: DatePlanStatus.done,
        scheduledAt: DateTime(2026, 9, 1, 19),
      ).toCalendarEvent();
      expect(done, isNotNull);
      expect(done!.location, isNull);
    });
  });

  group('DatePlanLists', () {
    final now = DateTime(2026, 10, 15, 12);

    test('ideas are newest first, unsaved ones on top', () {
      final list = DatePlanLists.ideas([
        plan('old', createdAt: DateTime(2026, 1, 1)),
        plan('new', createdAt: DateTime(2026, 10, 1)),
        plan('pending'),
        plan(
          'planned',
          status: DatePlanStatus.planned,
          scheduledAt: DateTime(2026, 11, 1),
        ),
      ]);
      expect(list.map((p) => p.id), ['pending', 'new', 'old']);
    });

    test('planned: upcoming soonest first, then past ones flagged', () {
      final all = [
        plan(
          'later',
          status: DatePlanStatus.planned,
          scheduledAt: DateTime(2026, 12, 1, 19),
        ),
        plan(
          'pastOld',
          status: DatePlanStatus.planned,
          scheduledAt: DateTime(2026, 9, 1, 19),
        ),
        plan(
          'tonight',
          status: DatePlanStatus.planned,
          scheduledAt: DateTime(2026, 10, 15, 19, 30),
        ),
        plan(
          'thisMorning',
          status: DatePlanStatus.planned,
          scheduledAt: DateTime(2026, 10, 15, 9),
        ),
        plan('idea'),
      ];
      expect(DatePlanLists.upcoming(all, now).map((p) => p.id), [
        'tonight',
        'later',
      ]);
      expect(DatePlanLists.needsRecap(all, now).map((p) => p.id), [
        'pastOld',
        'thisMorning',
      ]);
      expect(DatePlanLists.planned(all, now).map((p) => p.id), [
        'tonight',
        'later',
        'pastOld',
        'thisMorning',
      ]);
      expect(all[1].needsRecap(now), isTrue);
      expect(all[0].needsRecap(now), isFalse);
    });

    test('done: latest completed first, scheduled time as fallback', () {
      final list = DatePlanLists.done([
        plan(
          'a',
          status: DatePlanStatus.done,
          completedAt: DateTime(2026, 9, 1),
        ),
        plan(
          'b',
          status: DatePlanStatus.done,
          completedAt: DateTime(2026, 10, 1),
        ),
        plan(
          'legacy',
          status: DatePlanStatus.done,
          scheduledAt: DateTime(2026, 9, 15),
        ),
        plan('idea'),
      ]);
      expect(list.map((p) => p.id), ['b', 'legacy', 'a']);
    });

    test('surprise picks with the injected Random', () {
      final ideas = [plan('a'), plan('b'), plan('c')];
      expect(DatePlanLists.surprise(ideas, _FixedRandom([1]))!.id, 'b');
      expect(DatePlanLists.surprise(ideas, _FixedRandom([5]))!.id, 'c');
      expect(DatePlanLists.surprise(const [], _FixedRandom([0])), isNull);
    });

    test('surprise avoids repeating the previous pick', () {
      final ideas = [plan('a'), plan('b'), plan('c')];
      final random = _FixedRandom([0]);
      final pick = DatePlanLists.surprise(ideas, random, previousId: 'a');
      expect(pick!.id, 'b');
      expect(random.maxes, [2]);
      // With a single idea it may repeat.
      expect(
        DatePlanLists.surprise([plan('a')], random, previousId: 'a')!.id,
        'a',
      );
    });

    test('surprise over many draws only ever returns ideas given', () {
      final ideas = [plan('a'), plan('b')];
      final random = Random(7);
      final seen = <String>{};
      for (var i = 0; i < 50; i++) {
        seen.add(DatePlanLists.surprise(ideas, random)!.id);
      }
      expect(seen, {'a', 'b'});
    });

    test('countdown labels', () {
      expect(DatePlanLists.countdown(DateTime(2026, 10, 15, 20), now), 'Today');
      expect(
        DatePlanLists.countdown(DateTime(2026, 10, 16, 8), now),
        'Tomorrow',
      );
      expect(DatePlanLists.countdown(DateTime(2026, 10, 20), now), 'In 5 days');
      expect(DatePlanLists.countdown(DateTime(2026, 11, 5), now), 'In 3 weeks');
      expect(DatePlanLists.countdown(DateTime(2027, 1, 20), now), 'Jan 20');
    });
  });

  group('DatePlanCost', () {
    test('parses amounts into paise', () {
      expect(DatePlanCost.parseMinor('1,250.50'), 125050);
      expect(DatePlanCost.parseMinor('1250.5'), 125050);
      expect(DatePlanCost.parseMinor(' 499 '), 49900);
      expect(DatePlanCost.parseMinor('0'), 0);
      expect(DatePlanCost.parseMinor('0.05'), 5);
      expect(DatePlanCost.parseMinor('10000000'), DatePlan.maxCostMinor);
    });

    test('rejects bad input', () {
      expect(DatePlanCost.parseMinor(''), isNull);
      expect(DatePlanCost.parseMinor('-10'), isNull);
      expect(DatePlanCost.parseMinor('12.345'), isNull);
      expect(DatePlanCost.parseMinor('1.2.3'), isNull);
      expect(DatePlanCost.parseMinor('abc'), isNull);
      expect(DatePlanCost.parseMinor('.5'), isNull);
      expect(DatePlanCost.parseMinor('10000000.01'), isNull);
    });

    test('formats for display and for editing', () {
      expect(DatePlanCost.format(0, 'INR'), 'Free');
      expect(DatePlanCost.format(125000, 'INR'), '₹1,250');
      expect(DatePlanCost.format(125050, 'INR'), '₹1,250.50');
      expect(DatePlanCost.format(999, 'USD'), r'$9.99');
      expect(DatePlanCost.toInput(125050), '1250.50');
      expect(DatePlanCost.toInput(125000), '1250');
      expect(DatePlanCost.toInput(5), '0.05');
      expect(DatePlanCost.parseMinor(DatePlanCost.toInput(98765)), 98765);
    });
  });

  group('DatePlannerScreen', () {
    const me = AppUser(uid: 'u1', displayName: 'Asha', coupleId: 'c1');
    const partner = AppUser(uid: 'u2', displayName: 'Ravi', coupleId: 'c1');
    const couple = Couple(id: 'c1', inviteCode: 'X', memberIds: ['u1', 'u2']);

    late _FakeDatePlanService service;
    setUp(() => service = _FakeDatePlanService());

    Widget app(List<DatePlan> plans) => ProviderScope(
      overrides: [
        datePlanServiceProvider.overrideWithValue(service),
        currentUserProvider.overrideWithBuild((ref, notifier) => me),
        coupleProvider.overrideWith((ref) => Stream.value(couple)),
        partnerProvider.overrideWith((ref) => Stream.value(partner)),
        datePlansProvider.overrideWith((ref) => Stream.value(plans)),
      ],
      child: const MaterialApp(home: DatePlannerScreen()),
    );

    testWidgets('empty ideas invite the first one', (tester) async {
      await tester.pumpWidget(app(const []));
      await tester.pumpAndSettle();
      expect(find.text('No date ideas yet'), findsOneWidget);
      expect(find.textContaining('you and Ravi'), findsOneWidget);
      expect(find.text('Add an idea'), findsOneWidget);
      expect(find.text('Surprise me'), findsNothing);
    });

    testWidgets('segments, surprise card and marking a past date done', (
      tester,
    ) async {
      final soon = DateTime.now().add(const Duration(days: 3));
      await tester.pumpWidget(
        app([
          plan('i1', createdAt: DateTime(2026, 1, 1)),
          plan('i2', createdAt: DateTime(2026, 2, 1)),
          plan(
            'past',
            status: DatePlanStatus.planned,
            scheduledAt: DateTime(2024, 5, 4, 19),
          ),
          plan('soon', status: DatePlanStatus.planned, scheduledAt: soon),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Surprise me'), findsOneWidget);
      expect(find.text('Plan i1'), findsOneWidget);
      expect(find.text('Plan past'), findsNothing);

      await tester.tap(find.text('Planned 2'));
      await tester.pumpAndSettle();
      expect(find.text('Coming up'), findsOneWidget);
      expect(find.text('In 3 days'), findsOneWidget);
      expect(find.text('How did it go?'), findsWidgets);

      await tester.tap(find.text('Mark done'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('4 of 5'));
      await tester.enterText(find.byType(TextField), 'Lovely evening');
      await tester.tap(find.text('Save to done'));
      await tester.pumpAndSettle();
      expect(service.calls, ['markDone past 4 "Lovely evening"']);
    });
  });
}
