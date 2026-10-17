import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:couple_app/features/plans/models/bucket_item.dart';

/// Reads and writes `couples/{coupleId}/bucketList`.
class BucketListService {
  BucketListService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _items(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('bucketList');

  /// Every item on the shared list. Ordering is done by [BucketProgress].
  Stream<List<BucketItem>> watchItems(String coupleId) {
    return _items(
      coupleId,
    ).snapshots().map((snap) => snap.docs.map(BucketItem.fromDoc).toList());
  }

  /// Adds [item] when its id is empty, otherwise updates its editable
  /// fields (never the done state or the creator).
  Future<void> save(String coupleId, BucketItem item) async {
    if (item.id.isEmpty) {
      await _items(coupleId).add({
        ...item.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _items(coupleId).doc(item.id).set({
        ...item.toEditableMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Ticks an item off (recording who and when) or puts it back on the list.
  Future<void> setDone({
    required String coupleId,
    required String itemId,
    required bool done,
    required String uid,
  }) {
    return _items(coupleId).doc(itemId).update({
      'done': done,
      'doneAt': done ? FieldValue.serverTimestamp() : null,
      'doneBy': done ? uid : null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String coupleId, String itemId) {
    return _items(coupleId).doc(itemId).delete();
  }
}
