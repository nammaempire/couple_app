import 'package:couple_app/core/backend/backend.dart';

import 'package:couple_app/features/home/models/mood.dart';

/// Reads and writes the two partners' current moods.
///
/// Stored at `couples/{coupleId}/moods/{uid}` — one document each, overwritten
/// on every check-in rather than appended, since only "now" matters.
class MoodService {
  MoodService({Db? db}) : _db = db ?? Db.instance;

  final Db _db;

  CollectionReference<Map<String, dynamic>> _moods(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('moods');

  /// Both partners' moods, keyed by uid.
  Stream<Map<String, MoodEntry>> watchMoods(String coupleId) {
    return _moods(coupleId).snapshots().map((snap) {
      return {for (final doc in snap.docs) doc.id: MoodEntry.fromDoc(doc)};
    });
  }

  Future<void> setMood({
    required String coupleId,
    required String uid,
    required Mood mood,
    String note = '',
  }) {
    final entry = MoodEntry(uid: uid, mood: mood, note: note.trim());
    return _moods(coupleId).doc(uid).set(entry.toMap());
  }
}
