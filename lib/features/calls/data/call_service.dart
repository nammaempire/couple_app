import 'package:couple_app/core/backend/backend.dart';
import 'package:uuid/uuid.dart';

import 'package:couple_app/features/calls/models/call_session.dart';

/// Call signalling over Firestore.
///
/// Both phones watch one document; each state change (ring, accept, decline,
/// hang up) is a write both sides see. No dedicated signalling server needed.
class CallService {
  CallService({Db? db}) : _db = db ?? Db.instance;

  final Db _db;
  static final _uuid = Uuid();

  DocumentReference<Map<String, dynamic>> _callDoc(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('call').doc('current');

  /// The couple's current call document, or null when there is no call.
  Stream<CallSession?> watchCall(String coupleId) {
    return _callDoc(coupleId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return CallSession.fromDoc(doc);
    });
  }

  /// Places a call. Overwrites any previous call document, so a stale ended
  /// call never blocks a new one.
  Future<CallSession> startCall({
    required String coupleId,
    required String callerId,
    required String calleeId,
    required CallType type,
  }) async {
    final channelName = _uuid.v4().replaceAll('-', '');

    await _callDoc(coupleId).set({
      'callerId': callerId,
      'calleeId': calleeId,
      'type': type == CallType.video ? 'video' : 'voice',
      'status': 'ringing',
      'channelName': channelName,
      'startedAt': FieldValue.serverTimestamp(),
      'answeredAt': null,
      'endedAt': null,
    });

    return CallSession(
      callerId: callerId,
      calleeId: calleeId,
      type: type,
      status: CallStatus.ringing,
      channelName: channelName,
      startedAt: DateTime.now(),
    );
  }

  /// Answers the call. Returns false if it stopped ringing first (the
  /// caller hung up or it rang out), so a late tap cannot revive it.
  Future<bool> acceptCall(String coupleId) {
    final ref = _callDoc(coupleId);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data()?['status'] != 'ringing') return false;
      tx.update(ref, {
        'status': 'accepted',
        'answeredAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  Future<void> declineCall(String coupleId) {
    return _callDoc(
      coupleId,
    ).update({'status': 'declined', 'endedAt': FieldValue.serverTimestamp()});
  }

  /// Marks a still-ringing call as missed. Does nothing if it was answered
  /// or ended in the meantime, so a late accept is never overwritten.
  Future<void> markMissed(String coupleId) async {
    final ref = _callDoc(coupleId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data()?['status'] != 'ringing') return;
      tx.update(ref, {
        'status': 'missed',
        'endedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Hangs up, whether the call was connected or still ringing.
  Future<void> endCall(String coupleId) async {
    try {
      await _callDoc(
        coupleId,
      ).update({'status': 'ended', 'endedAt': FieldValue.serverTimestamp()});
    } on DbException catch (e) {
      // Nothing to end is not a failure worth surfacing to the user.
      if (e.code != 'not-found') rethrow;
    }
  }
}
