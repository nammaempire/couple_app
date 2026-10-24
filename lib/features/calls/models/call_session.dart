import 'package:couple_app/core/backend/backend.dart';

enum CallType { voice, video }

enum CallStatus {
  /// Caller has dialled; the other phone should be showing an incoming screen.
  ringing,

  /// Callee accepted. Both sides join the Agora channel.
  accepted,

  /// Callee actively rejected.
  declined,

  /// Either side hung up.
  ended,

  /// Nobody answered within [CallSession.ringTimeout].
  missed,
}

/// The single in-flight call for a couple.
///
/// A couple can only be in one call at a time, so this lives at a fixed
/// document path rather than a collection — which also means no stale
/// ringing documents pile up.
class CallSession {
  final String callerId;
  final String calleeId;
  final CallType type;
  final CallStatus status;

  /// Agora channel both sides join. Random per call.
  final String channelName;

  final DateTime? startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;

  const CallSession({
    required this.callerId,
    required this.calleeId,
    required this.type,
    required this.status,
    required this.channelName,
    this.startedAt,
    this.answeredAt,
    this.endedAt,
  });

  bool get isVideo => type == CallType.video;
  bool get isRinging => status == CallStatus.ringing;
  bool get isActive => status == CallStatus.accepted;

  /// True once the call is over, however it ended.
  bool get isFinished =>
      status == CallStatus.ended ||
      status == CallStatus.declined ||
      status == CallStatus.missed;

  /// A ringing call this user should be shown an incoming screen for.
  bool isIncomingFor(String uid) => isRinging && calleeId == uid;

  /// Unanswered calls expire so a missed call does not ring forever if the
  /// caller's app was killed before it could write `ended`.
  static const ringTimeout = Duration(seconds: 45);

  bool get hasRungOut {
    final at = startedAt;
    if (at == null) return false;
    return DateTime.now().difference(at) > ringTimeout;
  }

  factory CallSession.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return CallSession(
      callerId: (data['callerId'] as String?) ?? '',
      calleeId: (data['calleeId'] as String?) ?? '',
      type: (data['type'] as String?) == 'video'
          ? CallType.video
          : CallType.voice,
      status: _statusFrom(data['status'] as String?),
      channelName: (data['channelName'] as String?) ?? '',
      startedAt: (data['startedAt'] as Timestamp?)?.toDate(),
      answeredAt: (data['answeredAt'] as Timestamp?)?.toDate(),
      endedAt: (data['endedAt'] as Timestamp?)?.toDate(),
    );
  }

  static CallStatus _statusFrom(String? raw) {
    switch (raw) {
      case 'ringing':
        return CallStatus.ringing;
      case 'accepted':
        return CallStatus.accepted;
      case 'declined':
        return CallStatus.declined;
      case 'missed':
        return CallStatus.missed;
      default:
        return CallStatus.ended;
    }
  }
}
