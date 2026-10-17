import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/plans/data/bucket_list_service.dart';
import 'package:couple_app/features/plans/models/bucket_item.dart';
import 'package:couple_app/features/plans/models/bucket_progress.dart';
import 'package:couple_app/features/plans/providers/bucket_list_providers.dart';
import 'package:couple_app/features/plans/screens/bucket_list_screen.dart';

/// Records calls instead of touching Firestore.
class _FakeBucketListService implements BucketListService {
  final calls = <String>[];

  @override
  Future<void> setDone({
    required String coupleId,
    required String itemId,
    required bool done,
    required String uid,
  }) async => calls.add('setDone $itemId $done by $uid');

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

BucketItem item(
  String id, {
  BucketCategory category = BucketCategory.travel,
  bool done = false,
  DateTime? doneAt,
  DateTime? createdAt,
  int? targetYear,
}) => BucketItem(
  id: id,
  title: 'Item $id',
  category: category,
  done: done,
  doneAt: doneAt,
  doneBy: done ? 'u1' : null,
  targetYear: targetYear,
  createdBy: 'u1',
  createdAt: createdAt,
);

void main() {
  group('BucketCategory', () {
    test('fromId finds known ids and defaults to other', () {
      expect(BucketCategory.fromId('romance'), BucketCategory.romance);
      expect(BucketCategory.fromId('learn'), BucketCategory.learn);
      expect(BucketCategory.fromId('space'), BucketCategory.other);
      expect(BucketCategory.fromId(null), BucketCategory.other);
    });

    test('ids are unique and stable', () {
      expect(BucketCategory.values.map((c) => c.id).toSet().length, 7);
      expect(BucketCategory.values.map((c) => c.id), [
        'travel',
        'adventure',
        'food',
        'learn',
        'home',
        'romance',
        'other',
      ]);
    });
  });

  group('BucketItem map round-trip', () {
    test('toMap then fromMap keeps every field', () {
      final original = BucketItem(
        id: 'b1',
        title: '  Northern lights  ',
        notes: 'Tromsø in winter ',
        category: BucketCategory.adventure,
        done: true,
        doneAt: DateTime(2026, 3, 4, 21),
        doneBy: 'u2',
        targetYear: 2027,
        createdBy: 'u1',
      );
      final map = original.toMap();
      expect(map['title'], 'Northern lights');
      expect(map['notes'], 'Tromsø in winter');
      expect(map['category'], 'adventure');
      expect(map['doneAt'], isA<Timestamp>());
      expect(map.containsKey('createdAt'), isFalse);

      final back = BucketItem.fromMap('b1', map);
      expect(back.title, 'Northern lights');
      expect(back.category, BucketCategory.adventure);
      expect(back.done, isTrue);
      expect(back.doneAt, DateTime(2026, 3, 4, 21));
      expect(back.doneBy, 'u2');
      expect(back.targetYear, 2027);
      expect(back.createdBy, 'u1');
    });

    test('editable map leaves done state and creator alone', () {
      final map = item('b', done: true, targetYear: 2030).toEditableMap();
      expect(
        map.keys,
        unorderedEquals(['title', 'notes', 'category', 'targetYear']),
      );
    });

    test('tolerates missing and malformed fields', () {
      final empty = BucketItem.fromMap('x', {});
      expect(empty.title, '');
      expect(empty.notes, '');
      expect(empty.category, BucketCategory.other);
      expect(empty.done, isFalse);
      expect(empty.targetYear, isNull);

      final odd = BucketItem.fromMap('y', {
        'title': 42,
        'category': 7,
        'done': 'yes',
        'targetYear': 2028.0,
        'doneAt': 'yesterday',
        'createdBy': null,
      });
      expect(odd.title, '');
      expect(odd.category, BucketCategory.other);
      expect(odd.done, isFalse);
      expect(odd.targetYear, 2028);
      expect(odd.doneAt, isNull);
      expect(odd.createdBy, '');
    });

    test('a not-done item ignores stale doneAt/doneBy', () {
      final i = BucketItem.fromMap('z', {
        'done': false,
        'doneAt': Timestamp.fromDate(DateTime(2025)),
        'doneBy': 'u1',
      });
      expect(i.doneAt, isNull);
      expect(i.doneBy, isNull);
    });

    test('copyWith can clear the target year', () {
      final i = item('a', targetYear: 2027);
      expect(i.copyWith(title: 'New').targetYear, 2027);
      expect(i.copyWith(clearTargetYear: true).targetYear, isNull);
      expect(i.copyWith(targetYear: 2029).targetYear, 2029);
    });

    test('overdue only when not done and the year has passed', () {
      final now = DateTime(2026, 10, 15);
      expect(item('a', targetYear: 2025).isOverdue(now), isTrue);
      expect(item('b', targetYear: 2026).isOverdue(now), isFalse);
      expect(item('c', targetYear: 2025, done: true).isOverdue(now), isFalse);
      expect(item('d').isOverdue(now), isFalse);
    });
  });

  group('BucketProgress', () {
    test('counts, fraction and label', () {
      final list = [
        item('1', done: true),
        item('2', done: true),
        item('3'),
        item('4'),
        item('5'),
      ];
      final p = BucketProgress.of(list);
      expect(p.done, 2);
      expect(p.total, 5);
      expect(p.remaining, 3);
      expect(p.fraction, closeTo(0.4, 1e-9));
      expect(p.percent, 40);
      expect(p.label, '2 of 5 done');
      expect(p.isComplete, isFalse);
    });

    test('empty list is 0 and not complete', () {
      final p = BucketProgress.of(const []);
      expect(p.fraction, 0);
      expect(p.percent, 0);
      expect(p.isComplete, isFalse);
      expect(p.label, '0 of 0 done');
    });

    test('percent rounds down so it only says 100 when all done', () {
      final list = [
        for (var i = 0; i < 199; i++) item('$i', done: true),
        item('last'),
      ];
      expect(BucketProgress.of(list).percent, 99);
      expect(BucketProgress.of([item('a', done: true)]).isComplete, isTrue);
      expect(BucketProgress.of([item('a', done: true)]).percent, 100);
    });

    test('filter and countByCategory', () {
      final list = [
        item('1', category: BucketCategory.food),
        item('2', category: BucketCategory.food, done: true),
        item('3', category: BucketCategory.home),
      ];
      expect(BucketProgress.filter(list, null).length, 3);
      expect(
        BucketProgress.filter(list, BucketCategory.food).map((i) => i.id),
        ['1', '2'],
      );
      expect(BucketProgress.filter(list, BucketCategory.travel), isEmpty);
      expect(BucketProgress.countByCategory(list), {
        BucketCategory.food: 2,
        BucketCategory.home: 1,
      });
      final foodProgress = BucketProgress.of(
        BucketProgress.filter(list, BucketCategory.food),
      );
      expect(foodProgress.label, '1 of 2 done');
    });

    test('to do: target year soonest first, then newest, unsaved first', () {
      final list = [
        item('old', createdAt: DateTime(2025, 1, 1)),
        item('new', createdAt: DateTime(2026, 1, 1)),
        item('y2030', targetYear: 2030, createdAt: DateTime(2024)),
        item('y2027', targetYear: 2027, createdAt: DateTime(2024)),
        item('pending'),
        item('done', done: true, doneAt: DateTime(2026)),
      ];
      expect(BucketProgress.toDo(list).map((i) => i.id), [
        'y2027',
        'y2030',
        'pending',
        'new',
        'old',
      ]);
    });

    test('completed: most recently done first', () {
      final list = [
        item('a', done: true, doneAt: DateTime(2026, 1, 1)),
        item('b', done: true, doneAt: DateTime(2026, 6, 1)),
        item('c', done: true), // just ticked, server time not back yet
        item('d'),
      ];
      expect(BucketProgress.completed(list).map((i) => i.id), ['c', 'b', 'a']);
    });
  });

  group('BucketListScreen', () {
    const me = AppUser(uid: 'u1', displayName: 'Asha', coupleId: 'c1');
    const partner = AppUser(uid: 'u2', displayName: 'Ravi', coupleId: 'c1');
    const couple = Couple(id: 'c1', inviteCode: 'X', memberIds: ['u1', 'u2']);

    late _FakeBucketListService service;
    setUp(() => service = _FakeBucketListService());

    Widget app(List<BucketItem> items) => ProviderScope(
      overrides: [
        bucketListServiceProvider.overrideWithValue(service),
        currentUserProvider.overrideWithBuild((ref, notifier) => me),
        coupleProvider.overrideWith((ref) => Stream.value(couple)),
        partnerProvider.overrideWith((ref) => Stream.value(partner)),
        bucketItemsProvider.overrideWith((ref) => Stream.value(items)),
      ],
      child: const MaterialApp(home: BucketListScreen()),
    );

    testWidgets('shows progress, groups and who ticked it', (tester) async {
      await tester.pumpWidget(
        app([
          item('1', category: BucketCategory.food),
          const BucketItem(
            id: '2',
            title: 'Skydive',
            category: BucketCategory.adventure,
            done: true,
            doneBy: 'u2',
            createdBy: 'u1',
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 done'), findsOneWidget);
      expect(find.text('To do'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.textContaining('Ticked off by Ravi'), findsOneWidget);

      await tester.tap(find.byTooltip('Tick it off'));
      await tester.pumpAndSettle();
      expect(service.calls, ['setDone 1 true by u1']);

      await tester.tap(find.text('🍜 Food · 1'));
      await tester.pumpAndSettle();
      expect(find.text('0 of 1 done'), findsOneWidget);
      expect(find.text('Skydive'), findsNothing);
    });

    testWidgets('empty list invites the first dream', (tester) async {
      await tester.pumpWidget(app(const []));
      await tester.pumpAndSettle();
      expect(find.textContaining('No dreams on the list yet'), findsOneWidget);
      expect(find.text('Add a dream'), findsOneWidget);

      await tester.tap(find.text('Add a dream'));
      await tester.pumpAndSettle();
      expect(find.text('Add to your bucket list'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
