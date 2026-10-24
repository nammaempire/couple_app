import 'package:couple_app/core/backend/backend.dart';

/// How a phone passed sign-in protection (`users/{uid}/devices/{id}.via`).
enum DeviceVia {
  /// The account's very first phone, trusted without asking.
  first,

  /// The partner said "Yes, it's them".
  partner,

  /// The account's password or Google account confirmed it.
  email,

  /// Seven days passed without the owner saying "It wasn't me".
  wait;

  static DeviceVia fromName(String? name) => DeviceVia.values.firstWhere(
    (v) => v.name == name,
    orElse: () => DeviceVia.first,
  );

  /// How it reads in the phones list.
  String get label => switch (this) {
    first => 'First phone',
    partner => 'Approved by your partner',
    email => 'Confirmed with your account',
    wait => 'Added after a 7-day wait',
  };
}

/// A phone that has passed sign-in protection: `users/{uid}/devices/{id}`.
class KnownDevice {
  const KnownDevice({
    required this.id,
    required this.name,
    required this.via,
    this.addedAt,
    this.lastSeenAt,
  });

  /// The phone's random id from secure storage (the vault's device id).
  final String id;

  /// The phone's model, e.g. "Pixel 9" (at most [maxNameLength]).
  final String name;
  final DeviceVia via;

  /// Server time; null while a write is still pending.
  final DateTime? addedAt;

  /// Server time, refreshed at most once a day when the app opens.
  final DateTime? lastSeenAt;

  static const maxNameLength = 60;

  /// [name] trimmed to what the rules accept, never empty.
  static String clampName(String name) {
    final trimmed = name.trim().isEmpty ? 'Phone' : name.trim();
    return trimmed.length <= maxNameLength
        ? trimmed
        : trimmed.substring(0, maxNameLength);
  }

  /// When this phone was last seen, falling back to when it was added.
  DateTime? get seenAt => lastSeenAt ?? addedAt;

  factory KnownDevice.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return KnownDevice(
      id: doc.id,
      name: (data['name'] as String?) ?? 'Phone',
      via: DeviceVia.fromName(data['via'] as String?),
      addedAt: (data['addedAt'] as Timestamp?)?.toDate(),
      lastSeenAt: (data['lastSeenAt'] as Timestamp?)?.toDate(),
    );
  }
}
