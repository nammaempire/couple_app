import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/plans/data/date_plan_service.dart';
import 'package:couple_app/features/plans/data/place_service.dart';
import 'package:couple_app/features/plans/models/date_plan.dart';
import 'package:couple_app/features/plans/models/place.dart';
import 'package:couple_app/features/plans/providers/date_plan_providers.dart';
import 'package:couple_app/features/plans/providers/place_providers.dart';
import 'package:couple_app/features/plans/screens/places_screen.dart';

Place place(
  String id, {
  PlaceStatus status = PlaceStatus.wantToGo,
  PlaceCategory category = PlaceCategory.cafe,
  bool favourite = false,
  DateTime? createdAt,
  DateTime? visitedAt,
}) => Place(
  id: id,
  name: 'Place $id',
  createdBy: 'u1',
  status: status,
  category: category,
  favourite: favourite,
  createdAt: createdAt,
  visitedAt: visitedAt,
);

class _FakePlaceService implements PlaceService {
  final calls = <String>[];

  @override
  Future<void> setFavourite(
    String coupleId,
    String placeId,
    bool favourite,
  ) async => calls.add('favourite $placeId $favourite');

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _FakeDatePlanService implements DatePlanService {
  final saved = <DatePlan>[];

  @override
  Future<void> save(String coupleId, DatePlan plan) async => saved.add(plan);

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  group('Place fields', () {
    test('round-trips through toMap / fromMap', () {
      final original = Place(
        id: 'p1',
        name: ' Toit ',
        area: 'Indiranagar, Bengaluru',
        mapsUrl: 'https://maps.app.goo.gl/abc123',
        category: PlaceCategory.bar,
        status: PlaceStatus.been,
        rating: 4,
        visitedAt: DateTime(2026, 9, 20),
        notes: 'Try the stout',
        favourite: true,
        createdBy: 'u2',
      );
      final map = original.toMap();
      expect(map['name'], 'Toit');
      expect(map['category'], 'bar');
      expect(map['status'], 'been');
      expect(map['visitedAt'], isA<Timestamp>());
      expect(map.containsKey('createdAt'), isFalse);

      final back = Place.fromMap('p1', map);
      expect(back.name, 'Toit');
      expect(back.area, 'Indiranagar, Bengaluru');
      expect(back.mapsUrl, 'https://maps.app.goo.gl/abc123');
      expect(back.category, PlaceCategory.bar);
      expect(back.status, PlaceStatus.been);
      expect(back.rating, 4);
      expect(back.visitedAt, DateTime(2026, 9, 20));
      expect(back.notes, 'Try the stout');
      expect(back.favourite, isTrue);
      expect(back.createdBy, 'u2');
    });

    test('want-to-go places drop rating and visit date', () {
      final map = Place(
        id: 'p',
        name: 'Cafe',
        createdBy: 'u1',
        rating: 5,
        visitedAt: DateTime(2026, 1, 1),
      ).toMap();
      expect(map['rating'], isNull);
      expect(map['visitedAt'], isNull);
    });

    test('an invalid maps link is not stored', () {
      final map = Place(
        id: '',
        name: 'x',
        mapsUrl: 'javascript:alert(1)',
        createdBy: 'u1',
      ).toMap();
      expect(map['mapsUrl'], '');
    });

    test('malformed documents fall back to defaults', () {
      final p = Place.fromMap('m', {
        'name': 7,
        'category': 'museum',
        'status': 'visited',
        'rating': 0,
        'favourite': 'yes',
        'visitedAt': 123,
      });
      expect(p.name, '');
      expect(p.category, PlaceCategory.other);
      expect(p.status, PlaceStatus.wantToGo);
      expect(p.rating, isNull);
      expect(p.favourite, isFalse);
      expect(p.visitedAt, isNull);
      expect(Place.fromMap('e', const {}).mapsUrl, '');
    });

    test('enum fromId falls back safely', () {
      expect(PlaceCategory.fromId(null), PlaceCategory.other);
      expect(PlaceStatus.fromId('nope'), PlaceStatus.wantToGo);
      for (final c in PlaceCategory.values) {
        expect(PlaceCategory.fromId(c.id), c);
      }
      expect(PlaceStatus.fromId('been'), PlaceStatus.been);
    });
  });

  group('Maps links', () {
    test('search URL encodes name and area', () {
      expect(
        Place.mapsSearchUrl('Toit', 'Indiranagar, Bengaluru'),
        'https://www.google.com/maps/search/?api=1&query='
        'Toit%2C%20Indiranagar%2C%20Bengaluru',
      );
      expect(
        Place.mapsSearchUrl('Café & Co', ''),
        'https://www.google.com/maps/search/?api=1&query=Caf%C3%A9%20%26%20Co',
      );
    });

    test('open in Maps uses the saved link when it is a web link', () {
      const withLink = Place(
        id: 'a',
        name: 'Toit',
        mapsUrl: ' https://maps.app.goo.gl/xyz ',
        createdBy: 'u1',
      );
      expect(withLink.openInMapsUrl, 'https://maps.app.goo.gl/xyz');

      const withoutLink = Place(
        id: 'b',
        name: 'Nandi Hills',
        area: '',
        createdBy: 'u1',
      );
      expect(
        withoutLink.openInMapsUrl,
        'https://www.google.com/maps/search/?api=1&query=Nandi%20Hills',
      );

      const badLink = Place(
        id: 'c',
        name: 'Lalbagh',
        mapsUrl: 'lalbagh',
        createdBy: 'u1',
      );
      expect(badLink.openInMapsUrl, startsWith('https://www.google.com/maps'));
    });

    test('isWebUrl accepts http(s) with a host only', () {
      expect(Place.isWebUrl('https://maps.google.com/?q=x'), isTrue);
      expect(Place.isWebUrl('http://example.com'), isTrue);
      expect(Place.isWebUrl('ftp://example.com'), isFalse);
      expect(Place.isWebUrl('https://'), isFalse);
      expect(Place.isWebUrl('maps.google.com'), isFalse);
      expect(Place.isWebUrl(''), isFalse);
    });
  });

  group('Plan a date here', () {
    test('creates an idea titled after the place', () {
      const p = Place(
        id: 'x',
        name: 'Toit',
        area: 'Indiranagar',
        category: PlaceCategory.restaurant,
        createdBy: 'u2',
      );
      final idea = p.toDateIdea('u1');
      expect(idea.id, '');
      expect(idea.title, 'Date at Toit');
      expect(idea.location, 'Toit, Indiranagar');
      expect(idea.status, DatePlanStatus.idea);
      expect(idea.vibe, DateVibe.food);
      expect(idea.createdBy, 'u1');
    });

    test('stays within the date plan limits', () {
      final p = Place(
        id: 'x',
        name: 'n' * Place.maxName,
        area: 'a' * Place.maxArea,
        createdBy: 'u1',
      );
      final idea = p.toDateIdea('u1');
      expect(idea.title.length, lessThanOrEqualTo(DatePlan.maxTitle));
      expect(idea.location.length, lessThanOrEqualTo(DatePlan.maxLocation));
    });
  });

  group('PlaceLists', () {
    final all = [
      place('a', createdAt: DateTime(2026, 1, 1)),
      place('b', createdAt: DateTime(2026, 5, 1), favourite: true),
      place(
        'c',
        createdAt: DateTime(2026, 6, 1),
        category: PlaceCategory.outdoors,
      ),
      place('new'),
      place('been1', status: PlaceStatus.been, visitedAt: DateTime(2026, 3, 1)),
      place(
        'been2',
        status: PlaceStatus.been,
        visitedAt: DateTime(2026, 8, 1),
        category: PlaceCategory.outdoors,
      ),
    ];

    test('want to go: favourites first, then newest', () {
      expect(
        PlaceLists.filter(all, status: PlaceStatus.wantToGo).map((p) => p.id),
        ['b', 'new', 'c', 'a'],
      );
    });

    test('been: latest visit first', () {
      expect(
        PlaceLists.filter(all, status: PlaceStatus.been).map((p) => p.id),
        ['been2', 'been1'],
      );
    });

    test('category and favourites filters', () {
      expect(
        PlaceLists.filter(
          all,
          status: PlaceStatus.wantToGo,
          category: PlaceCategory.outdoors,
        ).map((p) => p.id),
        ['c'],
      );
      expect(
        PlaceLists.filter(
          all,
          status: PlaceStatus.wantToGo,
          favouritesOnly: true,
        ).map((p) => p.id),
        ['b'],
      );
    });

    test('counts and categories in use', () {
      expect(PlaceLists.count(all, PlaceStatus.wantToGo), 4);
      expect(PlaceLists.count(all, PlaceStatus.been), 2);
      expect(PlaceLists.categoriesUsed(all), [
        PlaceCategory.cafe,
        PlaceCategory.outdoors,
      ]);
    });
  });

  group('PlacesScreen', () {
    const me = AppUser(uid: 'u1', displayName: 'Asha', coupleId: 'c1');
    const partner = AppUser(uid: 'u2', displayName: 'Ravi', coupleId: 'c1');
    const couple = Couple(id: 'c1', inviteCode: 'X', memberIds: ['u1', 'u2']);

    late _FakePlaceService places;
    late _FakeDatePlanService plans;
    setUp(() {
      places = _FakePlaceService();
      plans = _FakeDatePlanService();
    });

    Widget app(List<Place> list) => ProviderScope(
      overrides: [
        placeServiceProvider.overrideWithValue(places),
        datePlanServiceProvider.overrideWithValue(plans),
        currentUserProvider.overrideWithBuild((ref, notifier) => me),
        coupleProvider.overrideWith((ref) => Stream.value(couple)),
        partnerProvider.overrideWith((ref) => Stream.value(partner)),
        placesProvider.overrideWith((ref) => Stream.value(list)),
      ],
      child: const MaterialApp(home: PlacesScreen()),
    );

    testWidgets('empty state names the partner', (tester) async {
      await tester.pumpWidget(app(const []));
      await tester.pumpAndSettle();
      expect(find.text('Where to next?'), findsOneWidget);
      expect(find.textContaining('you and Ravi'), findsOneWidget);
    });

    testWidgets('tabs, filters, favourite and plan a date here', (
      tester,
    ) async {
      await tester.pumpWidget(
        app([
          const Place(
            id: 'toit',
            name: 'Toit',
            area: 'Indiranagar',
            category: PlaceCategory.bar,
            createdBy: 'u2',
          ),
          place('park', category: PlaceCategory.outdoors),
          place('been', status: PlaceStatus.been),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Want to go · 2'), findsOneWidget);
      expect(find.text('Been there · 1'), findsOneWidget);
      expect(find.text('Toit'), findsOneWidget);

      await tester.tap(find.text('🌳 Outdoors'));
      await tester.pumpAndSettle();
      expect(find.text('Toit'), findsNothing);
      expect(find.text('Place park'), findsOneWidget);
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add to favourites').first);
      await tester.pumpAndSettle();
      expect(places.calls, ['favourite toit true']);

      await tester.tap(find.text('Toit'));
      await tester.pumpAndSettle();
      expect(find.textContaining('added by Ravi'), findsOneWidget);
      await tester.tap(find.text('Plan a date here'));
      await tester.pumpAndSettle();
      expect(plans.saved.single.title, 'Date at Toit');
      expect(plans.saved.single.location, 'Toit, Indiranagar');
      expect(plans.saved.single.createdBy, 'u1');
      expect(find.textContaining('added to your date ideas'), findsOneWidget);
    });
  });
}
