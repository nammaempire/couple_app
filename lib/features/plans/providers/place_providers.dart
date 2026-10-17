import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/plans/data/place_service.dart';
import 'package:couple_app/features/plans/models/place.dart';

final placeServiceProvider = Provider<PlaceService>((ref) => PlaceService());

/// Every saved place, unsorted. Filter and sort with `PlaceLists`. After an
/// error the last good list is kept in `.value`.
final placesProvider = StreamProvider.autoDispose<List<Place>>(
  (ref) => ref
      .watch(placeServiceProvider)
      .watchPlaces(ref.watch(currentCoupleIdProvider)),
);
