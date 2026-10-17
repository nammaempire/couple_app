import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:couple_app/features/home/models/love_tap.dart';
import 'package:couple_app/features/home/models/nudge.dart';

/// Sends and listens for nudges at `couples/{coupleId}/nudges`.
class NudgeService {
  NudgeService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _nudges(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('nudges');

  Future<void> send({
    required String coupleId,
    required String senderId,
    LoveTap kind = LoveTap.thinking,
  }) {
    return _nudges(coupleId).add({
      'senderId': senderId,
      'sentAt': FieldValue.serverTimestamp(),
      'kind': kind.id,
    });
  }

  /// The most recent nudge, whoever sent it.
  Stream<Nudge?> watchLatest(String coupleId) {
    return _nudges(
      coupleId,
    ).orderBy('sentAt', descending: true).limit(1).snapshots().map((snap) {
      if (snap.docs.isEmpty) return null;
      final doc = snap.docs.first;
      final data = doc.data();
      return Nudge(
        id: doc.id,
        senderId: (data['senderId'] as String?) ?? '',
        sentAt: (data['sentAt'] as Timestamp?)?.toDate(),
        kind: LoveTap.fromId(data['kind'] as String?),
      );
    });
  }
}
