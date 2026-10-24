import 'package:couple_app/core/backend/backend.dart';

/// Where a pair-by-number request stands.
enum PairRequestStatus {
  pending,
  accepted,
  declined,
  cancelled;

  static PairRequestStatus parse(Object? raw) => switch (raw) {
    'accepted' => PairRequestStatus.accepted,
    'declined' => PairRequestStatus.declined,
    'cancelled' => PairRequestStatus.cancelled,
    _ => PairRequestStatus.pending,
  };
}

/// "Asha wants to pair with you": `pairRequests/{id}`.
///
/// The sender offers their couple of one and its invite code; the receiver
/// accepts by joining with that code, exactly as if they had typed it.
class PairRequest {
  const PairRequest({
    required this.id,
    required this.fromUid,
    required this.fromName,
    required this.fromPhone,
    required this.toUid,
    required this.toPhone,
    required this.coupleId,
    required this.inviteCode,
    required this.status,
    this.createdAt,
  });

  /// Longest sender name the rules accept.
  static const maxNameLength = 60;

  final String id;
  final String fromUid;
  final String fromName;

  /// E.164, or empty when the sender has no number on their account.
  final String fromPhone;
  final String toUid;
  final String toPhone;
  final String coupleId;
  final String inviteCode;
  final PairRequestStatus status;
  final DateTime? createdAt;

  bool get isPending => status == PairRequestStatus.pending;

  factory PairRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    String text(String key) => (d[key] as String?) ?? '';
    final name = text('fromName').trim();
    return PairRequest(
      id: doc.id,
      fromUid: text('fromUid'),
      fromName: name.isEmpty ? 'Someone' : name,
      fromPhone: text('fromPhone'),
      toUid: text('toUid'),
      toPhone: text('toPhone'),
      coupleId: text('coupleId'),
      inviteCode: text('inviteCode'),
      status: PairRequestStatus.parse(d['status']),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
