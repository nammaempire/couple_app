import 'dart:convert';

import 'package:couple_app/core/backend/backend.dart';

/// One WebRTC setup message between the two phones.
class CallSignal {
  const CallSignal({
    required this.id,
    required this.from,
    required this.kind,
    required this.payload,
  });

  final String id;
  final String from;

  /// 'offer', 'answer' or 'candidates'.
  final String kind;
  final Map<String, dynamic> payload;
}

/// Call setup over the Us server, at `couples/{coupleId}/callSignals`.
///
/// To connect, the two phones swap an offer, an answer and batches of network
/// candidates. Each is a small document only the couple can read; once the
/// phones are connected, audio and video flow directly between them.
class CallSignaling {
  /// [_db] overrides [Db.instance] (tests).
  CallSignaling([this._db]);

  final Db? _db;
  Db get _store => _db ?? Db.instance;

  CollectionReference<Map<String, dynamic>> _signals(String coupleId) =>
      _store.collection('couples').doc(coupleId).collection('callSignals');

  Future<void> send({
    required String coupleId,
    required String callId,
    required String from,
    required String to,
    required String kind,
    required Map<String, dynamic> payload,
  }) {
    return _signals(coupleId).add({
      'from': from,
      'to': to,
      'callId': callId,
      'kind': kind,
      'payload': jsonEncode(payload),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Every signal for [callId] addressed to [to], oldest first. Re-emits the
  /// whole list when one arrives; callers skip ids they have handled.
  Stream<List<CallSignal>> watch({
    required String coupleId,
    required String callId,
    required String to,
  }) {
    return _signals(coupleId)
        .where('callId', isEqualTo: callId)
        .where('to', isEqualTo: to)
        .orderBy('createdAt')
        .limit(500)
        .snapshots()
        .map(
          (snap) => [
            for (final doc in snap.docs)
              if (_decode(doc.data()['payload']) case final payload?)
                CallSignal(
                  id: doc.id,
                  from: (doc.data()['from'] as String?) ?? '',
                  kind: (doc.data()['kind'] as String?) ?? '',
                  payload: payload,
                ),
          ],
        );
  }

  /// Removes setup messages from earlier calls (best effort).
  Future<void> clear(String coupleId) async {
    final old = await _signals(coupleId).limit(400).get();
    if (old.docs.isEmpty) return;
    final batch = _store.batch();
    for (final doc in old.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  static Map<String, dynamic>? _decode(Object? raw) {
    if (raw is! String) return null;
    try {
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }
}
