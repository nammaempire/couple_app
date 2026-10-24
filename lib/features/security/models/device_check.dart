import 'package:couple_app/core/backend/backend.dart';

/// Where a partner check stands.
enum DeviceCheckStatus {
  pending,
  approved,
  rejected;

  static DeviceCheckStatus fromName(String? name) =>
      DeviceCheckStatus.values.firstWhere(
        (s) => s.name == name,
        orElse: () => DeviceCheckStatus.pending,
      );
}

/// A new phone asking the partner to vouch for it:
/// `couples/{cid}/deviceChecks/{id}`.
class DeviceCheck {
  const DeviceCheck({
    required this.id,
    required this.uid,
    required this.deviceId,
    required this.deviceName,
    required this.code,
    required this.status,
    this.createdAt,
    this.decidedBy,
    this.decidedAt,
  });

  final String id;

  /// Who signed in on the new phone.
  final String uid;
  final String deviceId;
  final String deviceName;

  /// The two-digit number shown on the new phone (10–99), which the
  /// partner asks about before saying yes.
  final int code;
  final DeviceCheckStatus status;

  /// Server time; null while the write is pending.
  final DateTime? createdAt;

  /// The partner who answered.
  final String? decidedBy;
  final DateTime? decidedAt;

  /// Pending checks older than this aren't shown to the partner any more;
  /// the new phone makes a fresh one.
  static const maxAge = Duration(hours: 24);

  bool get isPending => status == DeviceCheckStatus.pending;

  /// Whether the partner should still be asked about it at [now].
  bool isFreshAt(DateTime now) {
    final at = createdAt;
    return at == null || now.difference(at) < maxAge;
  }

  factory DeviceCheck.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return DeviceCheck(
      id: doc.id,
      uid: (data['uid'] as String?) ?? '',
      deviceId: (data['deviceId'] as String?) ?? '',
      deviceName: (data['deviceName'] as String?) ?? 'Phone',
      code: (data['code'] as num?)?.toInt() ?? 0,
      status: DeviceCheckStatus.fromName(data['status'] as String?),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      decidedBy: data['decidedBy'] as String?,
      decidedAt: (data['decidedAt'] as Timestamp?)?.toDate(),
    );
  }
}
