import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:couple_app/features/premium/models/gift.dart';

/// Gifts between the partners. The server creates them; the recipient
/// only marks one opened.
class GiftService {
  GiftService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _gifts(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('gifts');

  /// Every gift in the couple, newest first.
  Stream<List<Gift>> watchGifts(String coupleId) =>
      _gifts(coupleId).snapshots().map((snap) {
        final epoch = DateTime.fromMillisecondsSinceEpoch(0);
        return snap.docs.map(Gift.fromDoc).toList()..sort(
          (a, b) => (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch),
        );
      });

  /// The recipient opens [gift]: sets `openedAt` once, and nothing else.
  Future<void> markOpened({required String coupleId, required Gift gift}) {
    if (gift.isOpened) return Future.value();
    return _gifts(
      coupleId,
    ).doc(gift.id).update({'openedAt': FieldValue.serverTimestamp()});
  }
}
