import 'package:couple_app/core/backend/backend.dart';

import 'package:couple_app/features/plans/models/place.dart';

/// Reads and writes `couples/{coupleId}/places`.
class PlaceService {
  PlaceService({Db? db}) : _db = db ?? Db.instance;

  final Db _db;

  CollectionReference<Map<String, dynamic>> _places(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('places');

  /// Every saved place, unsorted (see `PlaceLists`).
  Stream<List<Place>> watchPlaces(String coupleId) {
    return _places(
      coupleId,
    ).snapshots().map((snap) => snap.docs.map(Place.fromDoc).toList());
  }

  /// Adds [place] when its id is empty, otherwise updates it.
  Future<void> save(String coupleId, Place place) async {
    final data = place.toMap();
    if (place.id.isEmpty) {
      await _places(
        coupleId,
      ).add({...data, 'createdAt': FieldValue.serverTimestamp()});
    } else {
      await _places(coupleId).doc(place.id).set({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> setFavourite(String coupleId, String placeId, bool favourite) {
    return _places(coupleId).doc(placeId).update({
      'favourite': favourite,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Marks a place as visited on [visitedAt] (a local date), with an
  /// optional 1–5 rating and notes.
  Future<void> markBeen(
    String coupleId,
    String placeId, {
    required DateTime visitedAt,
    int? rating,
    required String notes,
  }) {
    final day = DateTime(visitedAt.year, visitedAt.month, visitedAt.day);
    final trimmed = notes.trim();
    return _places(coupleId).doc(placeId).update({
      'status': PlaceStatus.been.id,
      'visitedAt': Timestamp.fromDate(day),
      'rating': rating,
      'notes': trimmed.length > Place.maxNotes
          ? trimmed.substring(0, Place.maxNotes)
          : trimmed,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Moves a place back to "Want to go", clearing the visit.
  Future<void> markWantToGo(String coupleId, String placeId) {
    return _places(coupleId).doc(placeId).update({
      'status': PlaceStatus.wantToGo.id,
      'visitedAt': null,
      'rating': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String coupleId, String placeId) {
    return _places(coupleId).doc(placeId).delete();
  }
}
