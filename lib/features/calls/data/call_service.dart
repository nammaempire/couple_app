import 'package:couple_app/core/backend/backend.dart';
import 'package:uuid/uuid.dart';

import 'package:couple_app/features/calls/data/call_signaling.dart';
import 'package:couple_app/features/calls/models/call_session.dart';

/// Call state on the Us server: ringing, accepted, declined, ended, missed.
///
/// Both phones watch one document; each state change (ring, accept, decline,
/// hang up) is a write both sides see. The WebRTC connection itself is set up
/// through [CallSignaling] once the call is accepted.
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

  /// How long a call nobody ended keeps the line busy (both phones went
  /// off mid-call). Must match the server rules.
  static const ringHold = Duration(seconds: 60);
  static const talkHold = Duration(hours: 4);

  /// Whether [call] is still ringing or in progress, so a new call must not
  /// replace it.
  static bool isBusy(CallSession? call, {DateTime? now}) {
    final started = call?.startedAt;
    if (call == null || started == null) return false;
    final age = (now ?? DateTime.now()).difference(started);
    if (call.isRinging) return age < ringHold;
    if (call.isActive) return age < talkHold;
    return false;
  }

  /// Places a call. Replaces the previous call document once that call is
  /// over (a stale one never blocks a new call), but throws
  /// [CallBusyException] while a call is still ringing or going on: say,
  /// both partners pressed call at the same moment. The server refuses it
  /// too.
  Future<CallSession> startCall({
    required String coupleId,
    required String callerId,
    required String calleeId,
    required CallType type,
  }) async {
    final current = await _callDoc(coupleId).get();
    if (current.exists) {
      final call = CallSession.fromDoc(current);
      if (isBusy(call)) {
        throw CallBusyException(
          incoming: call.isRinging && call.callerId == calleeId,
        );
      }
    }

    final channelName = _uuid.v4().replaceAll('-', '');
    // Setup messages from earlier calls are no longer needed.
    try {
      await CallSignaling(_db).clear(coupleId);
    } catch (_) {}

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

/// A call couldn't be placed because another one is ringing or going on.
class CallBusyException implements Exception {
  const CallBusyException({required this.incoming});

  /// The partner is calling this phone right now (both pressed call).
  final bool incoming;

  @override
  String toString() => 'CallBusyException(incoming: $incoming)';
}
