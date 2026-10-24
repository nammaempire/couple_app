import 'package:couple_app/core/backend/backend.dart';

/// What happened (`users/{uid}/securityEvents/{id}.type`).
enum SecurityEventType {
  /// The partner said a new phone wasn't this user.
  newPhoneRejected,

  /// A new phone with no other way in started the 7-day wait.
  newPhoneWaiting,

  /// A new phone passed sign-in protection.
  newPhoneApproved;

  static SecurityEventType? fromName(String? name) {
    for (final t in values) {
      if (t.name == name) return t;
    }
    return null;
  }
}

/// A notice for the account owner's phones: `users/{uid}/securityEvents/{id}`.
///
/// Ids say which phone an event is about, so that phone can leave out its
/// own notices: `wait_{deviceId}` (one per waiting phone, whose `at` is
/// when its wait began) and `approved_{deviceId}_{millis}`.
class SecurityEvent {
  const SecurityEvent({
    required this.id,
    required this.type,
    required this.deviceName,
    this.at,
  });

  final String id;
  final SecurityEventType type;
  final String deviceName;

  /// Server time; null while the write is pending.
  final DateTime? at;

  static String waitId(String deviceId) => 'wait_$deviceId';

  static String approvedId(String deviceId, DateTime now) =>
      'approved_${deviceId}_${now.millisecondsSinceEpoch}';

  /// Whether this notice is about the phone [deviceId] itself.
  bool isAbout(String deviceId) =>
      id == waitId(deviceId) || id.startsWith('approved_${deviceId}_');

  /// Null for a type this version doesn't know.
  static SecurityEvent? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final type = SecurityEventType.fromName(data['type'] as String?);
    if (type == null) return null;
    return SecurityEvent(
      id: doc.id,
      type: type,
      deviceName: (data['deviceName'] as String?) ?? 'a phone',
      at: (data['at'] as Timestamp?)?.toDate(),
    );
  }
}
