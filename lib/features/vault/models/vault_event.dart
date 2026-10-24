import 'package:couple_app/core/backend/backend.dart';
import 'package:flutter/foundation.dart';

/// Something the other partner should know about the vault.
enum VaultEventType {
  wrongCode,
  cooldown,
  codeChanged,
  deviceAdded,
  deviceApproved,
  wiped;

  static VaultEventType? fromName(Object? name) {
    for (final t in values) {
      if (t.name == name) return t;
    }
    return null;
  }
}

/// An alert: `couples/{cid}/vaultEvents/{id}`. Dismissing deletes it.
@immutable
class VaultEvent {
  const VaultEvent({
    required this.id,
    required this.type,
    required this.uid,
    required this.deviceName,
    this.at,
  });

  final String id;
  final VaultEventType type;

  /// Who caused it.
  final String uid;
  final String deviceName;
  final DateTime? at;

  /// The alert line, for the partner who didn't cause it.
  String describe(String name) => switch (type) {
    VaultEventType.wrongCode =>
      'Someone entered wrong codes on $name\'s $deviceName',
    VaultEventType.cooldown =>
      'Too many wrong codes on $name\'s $deviceName. It\'s paused for a while',
    VaultEventType.codeChanged => '$name changed a vault code',
    VaultEventType.deviceAdded =>
      '$name added a phone ($deviceName). It needs approval',
    VaultEventType.deviceApproved => '$name approved a phone',
    VaultEventType.wiped => '$name deleted the vault',
  };

  /// Whether it's a warning rather than news.
  bool get isWarning =>
      type == VaultEventType.wrongCode || type == VaultEventType.cooldown;

  static VaultEvent? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    final type = VaultEventType.fromName(data['type']);
    if (type == null) return null;
    return VaultEvent(
      id: doc.id,
      type: type,
      uid: (data['uid'] as String?) ?? '',
      deviceName: (data['deviceName'] as String?) ?? 'phone',
      at: (data['at'] as Timestamp?)?.toDate(),
    );
  }
}
