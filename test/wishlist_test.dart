import 'package:couple_app/core/backend/backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/plans/data/wishlist_service.dart';
import 'package:couple_app/features/plans/models/wishlist_claim.dart';
import 'package:couple_app/features/plans/models/wishlist_item.dart';
import 'package:couple_app/features/plans/models/wishlist_price.dart';
import 'package:couple_app/features/plans/providers/wishlist_providers.dart';
import 'package:couple_app/features/plans/screens/wishlist_item_editor_screen.dart';
import 'package:couple_app/features/plans/screens/wishlist_screen.dart';

/// Records calls instead of touching the database.
class _FakeWishlistService implements WishlistService {
  final calls = <String>[];

  @override
  Future<void> claim({
    required String coupleId,
    required WishlistItem item,
    required String myUid,
  }) async => calls.add('claim ${item.id} by $myUid for ${item.createdBy}');

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

WishlistItem wish(
  String id, {
  WishlistPriority priority = WishlistPriority.like,
  DateTime? createdAt,
}) => WishlistItem(
  id: id,
  title: 'Wish $id',
  priority: priority,
  createdBy: 'u1',
  createdAt: createdAt,
);

void main() {
  group('Enums', () {
    test('priority fromId and default', () {
      expect(WishlistPriority.fromId('love'), WishlistPriority.love);
      expect(WishlistPriority.fromId('someday'), WishlistPriority.someday);
      expect(WishlistPriority.fromId('urgent'), WishlistPriority.like);
      expect(WishlistPriority.fromId(null), WishlistPriority.like);
    });

    test('occasion fromId and default', () {
      expect(WishlistOccasion.fromId('festival'), WishlistOccasion.festival);
      expect(WishlistOccasion.fromId('birthday'), WishlistOccasion.birthday);
      expect(WishlistOccasion.fromId('diwali'), WishlistOccasion.any);
      expect(WishlistOccasion.fromId(null), WishlistOccasion.any);
    });
  });

  group('WishlistItem map round-trip', () {
    test('toMap then fromMap keeps every field', () {
      const original = WishlistItem(
        id: 'w1',
        title: ' Film camera ',
        notes: 'Olympus mju II',
        url: 'https://example.com/camera',
        priceMinor: 1250050,
        priority: WishlistPriority.love,
        occasion: WishlistOccasion.birthday,
        createdBy: 'u2',
        received: true,
      );
      final map = original.toMap();
      expect(map['title'], 'Film camera');
      expect(map['priority'], 'love');
      expect(map['occasion'], 'birthday');
      expect(map['priceMinor'], 1250050);
      expect(map['priceMinor'], isA<int>());
      expect(map.containsKey('createdAt'), isFalse);

      final back = WishlistItem.fromMap('w1', {
        ...map,
        'createdAt': Timestamp.fromDate(DateTime(2026, 5, 1)),
      });
      expect(back.title, 'Film camera');
      expect(back.notes, 'Olympus mju II');
      expect(back.url, 'https://example.com/camera');
      expect(back.priceMinor, 1250050);
      expect(back.priority, WishlistPriority.love);
      expect(back.occasion, WishlistOccasion.birthday);
      expect(back.createdBy, 'u2');
      expect(back.received, isTrue);
      expect(back.createdAt, DateTime(2026, 5, 1));
    });

    test('editable map never touches owner or received', () {
      final map = wish('a').toEditableMap();
      expect(map.containsKey('createdBy'), isFalse);
      expect(map.containsKey('received'), isFalse);
    });

    test('tolerates missing and malformed fields', () {
      final empty = WishlistItem.fromMap('x', {});
      expect(empty.title, '');
      expect(empty.url, '');
      expect(empty.priceMinor, isNull);
      expect(empty.priority, WishlistPriority.like);
      expect(empty.occasion, WishlistOccasion.any);
      expect(empty.received, isFalse);

      final odd = WishlistItem.fromMap('y', {
        'title': 3,
        'url': 'javascript:alert(1)',
        'priceMinor': -5,
        'priority': 9,
        'received': 'true',
      });
      expect(odd.title, '');
      expect(odd.url, '', reason: 'unsafe links are dropped');
      expect(odd.priceMinor, isNull);
      expect(odd.priority, WishlistPriority.like);
      expect(odd.received, isFalse);
      expect(WishlistItem.fromMap('z', {'priceMinor': 199.0}).priceMinor, 199);
    });

    test('copyWith can clear the price', () {
      const w = WishlistItem(
        id: 'a',
        title: 't',
        createdBy: 'u',
        priceMinor: 5,
      );
      expect(w.copyWith(title: 'x').priceMinor, 5);
      expect(w.copyWith(clearPrice: true).priceMinor, isNull);
    });
  });

  group('Sorting', () {
    test('priority first, then newest; unsaved counts as newest', () {
      final list = [
        wish(
          'some-new',
          priority: WishlistPriority.someday,
          createdAt: DateTime(2026, 9),
        ),
        wish('like-old', createdAt: DateTime(2025)),
        wish(
          'love-old',
          priority: WishlistPriority.love,
          createdAt: DateTime(2024),
        ),
        wish('like-new', createdAt: DateTime(2026)),
        wish(
          'love-new',
          priority: WishlistPriority.love,
          createdAt: DateTime(2026, 2),
        ),
        wish('like-pending'),
      ];
      expect(WishlistItem.sorted(list).map((w) => w.id), [
        'love-new',
        'love-old',
        'like-pending',
        'like-new',
        'like-old',
        'some-new',
      ]);
    });

    test('does not modify the input', () {
      final list = [wish('b', priority: WishlistPriority.someday), wish('a')];
      WishlistItem.sorted(list);
      expect(list.first.id, 'b');
    });
  });

  group('Links', () {
    test('valid: empty or http(s) with a host', () {
      expect(WishlistItem.isValidUrl(''), isTrue);
      expect(WishlistItem.isValidUrl('https://amazon.in/dp/1'), isTrue);
      expect(WishlistItem.isValidUrl('HTTP://example.com'), isTrue);
      expect(WishlistItem.isValidUrl('ftp://example.com'), isFalse);
      expect(WishlistItem.isValidUrl('example.com'), isFalse);
      expect(WishlistItem.isValidUrl('https://'), isFalse);
      expect(
        WishlistItem.isValidUrl('https://a.com/${'x' * 2000}'),
        isFalse,
        reason: 'over 2000 characters',
      );
    });

    test('normalize adds https when the scheme is missing', () {
      expect(WishlistItem.normalizeUrl('  '), '');
      expect(
        WishlistItem.normalizeUrl(' amazon.in/dp/1 '),
        'https://amazon.in/dp/1',
      );
      expect(WishlistItem.normalizeUrl('http://shop.com'), 'http://shop.com');
      // Other schemes are left as typed, and then fail validation.
      final ftp = WishlistItem.normalizeUrl('ftp://x.com');
      expect(ftp, 'ftp://x.com');
      expect(WishlistItem.isValidUrl(ftp), isFalse);
    });
  });

  group('WishlistPrice', () {
    test('parses into integer minor units', () {
      expect(WishlistPrice.parse('1,250.50').minor, 125050);
      expect(WishlistPrice.parse('1250').minor, 125000);
      expect(WishlistPrice.parse('1250.5').minor, 125050);
      expect(WishlistPrice.parse('0.99').minor, 99);
      expect(WishlistPrice.parse('12.').minor, 1200);
      expect(WishlistPrice.parse('0').minor, 0);
      expect(WishlistPrice.parse('0').isValid, isTrue);
    });

    test('empty is valid with no price', () {
      final p = WishlistPrice.parse('  ');
      expect(p.isValid, isTrue);
      expect(p.minor, isNull);
    });

    test('rejects junk, negatives, extra decimals and too much', () {
      for (final bad in [
        'abc',
        '-5',
        '1.234',
        '1.2.3',
        '.5',
        '10000001',
        '99999999999999999999',
      ]) {
        expect(WishlistPrice.parse(bad).isValid, isFalse, reason: bad);
      }
      expect(WishlistPrice.parse('10000000').minor, WishlistPrice.maxMinor);
    });

    test('toInput is the inverse of parse', () {
      for (final minor in [0, 5, 99, 100, 125050, 125000, 1000000000]) {
        final text = WishlistPrice.toInput(minor);
        expect(WishlistPrice.parse(text).minor, minor, reason: text);
      }
      expect(WishlistPrice.toInput(125005), '1250.05');
      expect(WishlistPrice.toInput(null), '');
    });

    test('formats with the currency, dropping .00', () {
      expect(WishlistPrice.format(125000, 'INR'), contains('1,250'));
      expect(WishlistPrice.format(125000, 'INR'), isNot(contains('.')));
      expect(WishlistPrice.format(125050, 'USD'), r'$1,250.50');
    });
  });

  group('WishlistClaim', () {
    test('round-trips without a client claimedAt', () {
      const claim = WishlistClaim(
        itemId: 'w1',
        claimedBy: 'me',
        itemOwner: 'partner',
        purchased: true,
      );
      final map = claim.toMap();
      expect(map, {
        'claimedBy': 'me',
        'itemOwner': 'partner',
        'purchased': true,
      });
      final back = WishlistClaim.fromMap('w1', {
        ...map,
        'claimedAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
      });
      expect(back.itemId, 'w1');
      expect(back.claimedBy, 'me');
      expect(back.itemOwner, 'partner');
      expect(back.purchased, isTrue);
      expect(back.claimedAt, DateTime(2026, 10, 1));
    });

    test('tolerates a partial doc', () {
      final c = WishlistClaim.fromMap('w', {});
      expect(c.claimedBy, '');
      expect(c.purchased, isFalse);
      expect(c.claimedAt, isNull);
    });

    test('byItem keys by item id and keeps only my claims', () {
      final map = WishlistClaim.byItem([
        const WishlistClaim(itemId: 'a', claimedBy: 'me', itemOwner: 'p'),
        const WishlistClaim(itemId: 'b', claimedBy: 'p', itemOwner: 'me'),
      ], 'me');
      expect(map.keys, ['a']);
    });
  });

  group('WishlistScreen', () {
    const me = AppUser(uid: 'me', displayName: 'Asha', coupleId: 'c1');
    const partner = AppUser(uid: 'p', displayName: 'Ravi', coupleId: 'c1');
    const couple = Couple(id: 'c1', inviteCode: 'X', memberIds: ['me', 'p']);

    final items = [
      const WishlistItem(
        id: 'mine',
        title: 'Hiking boots',
        priceMinor: 450000,
        priority: WishlistPriority.love,
        createdBy: 'me',
      ),
      const WishlistItem(
        id: 'theirs-claimed',
        title: 'Vinyl player',
        createdBy: 'p',
      ),
      const WishlistItem(
        id: 'theirs-free',
        title: 'Fountain pen',
        url: 'https://example.com/pen',
        createdBy: 'p',
      ),
    ];

    late _FakeWishlistService service;
    setUp(() => service = _FakeWishlistService());

    Widget app(Widget home, {Map<String, WishlistClaim> claims = const {}}) =>
        ProviderScope(
          overrides: [
            wishlistServiceProvider.overrideWithValue(service),
            currentUserProvider.overrideWithBuild((ref, notifier) => me),
            coupleProvider.overrideWith((ref) => Stream.value(couple)),
            partnerProvider.overrideWith((ref) => Stream.value(partner)),
            wishlistItemsProvider.overrideWith((ref) => Stream.value(items)),
            myWishlistClaimsProvider.overrideWith(
              (ref) => Stream.value(claims),
            ),
          ],
          child: MaterialApp(home: home),
        );

    testWidgets('my wishes never show claim state', (tester) async {
      await tester.pumpWidget(
        app(
          const WishlistScreen(),
          // Even a (bogus) claim keyed by my own item must not surface.
          claims: {
            'mine': const WishlistClaim(
              itemId: 'mine',
              claimedBy: 'me',
              itemOwner: 'me',
            ),
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hiking boots'), findsOneWidget);
      expect(find.text("Ravi's wishes"), findsOneWidget);
      expect(find.textContaining("won't see"), findsNothing);
      expect(find.text("You're getting this"), findsNothing);
      expect(find.text('Add a wish'), findsOneWidget);
    });

    testWidgets('partner tab shows my secret claims', (tester) async {
      await tester.pumpWidget(
        app(
          const WishlistScreen(),
          claims: {
            'theirs-claimed': const WishlistClaim(
              itemId: 'theirs-claimed',
              claimedBy: 'me',
              itemOwner: 'p',
            ),
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text("Ravi's wishes"));
      await tester.pumpAndSettle();
      expect(find.text('Vinyl player'), findsOneWidget);
      expect(find.text("You're getting this"), findsOneWidget);
      expect(find.text('Bought it'), findsOneWidget);
      expect(find.text("I'll get this"), findsOneWidget);
      expect(find.text("Ravi won't see this"), findsNWidgets(2));
      expect(find.text('Hiking boots'), findsNothing);
      expect(find.text('Add a wish'), findsNothing);

      await tester.tap(find.text("I'll get this"));
      await tester.pumpAndSettle();
      expect(service.calls, ['claim theirs-free by me for p']);
    });

    testWidgets('editor lays out on a small phone', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(WishlistItemEditorScreen(item: items[0])));
      await tester.pumpAndSettle();
      expect(find.text('Edit wish'), findsOneWidget);
      expect(find.text('4500'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
