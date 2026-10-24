import 'package:couple_app/core/backend/backend.dart';
import 'package:flutter/foundation.dart';

import 'package:couple_app/features/vault/data/vault_crypto.dart';

/// A phone registered for the vault: `vault/meta.devices.{id}`.
@immutable
class VaultDevice {
  const VaultDevice({
    required this.id,
    required this.uid,
    required this.publicKey,
    required this.name,
    required this.approved,
    this.addedAt,
  });

  final String id;

  /// Whose phone it is.
  final String uid;

  /// Base64 X25519 public key.
  final String publicKey;

  /// The phone's model or name, e.g. "Pixel 8".
  final String name;

  /// Approved by an already-approved phone (or the creator's phone).
  final bool approved;

  final DateTime? addedAt;

  /// The safety code both phones show when approving.
  String get fingerprint => deviceFingerprint(publicKey);

  /// The map stored for a new device. [addedAt] is the server's time.
  Map<String, dynamic> toNewMap() => {
    'uid': uid,
    'publicKey': publicKey,
    'name': name,
    'approved': approved,
    'addedAt': FieldValue.serverTimestamp(),
  };

  static VaultDevice? fromMap(String id, Object? map) {
    if (map is! Map) return null;
    final uid = map['uid'];
    final publicKey = map['publicKey'];
    if (uid is! String || publicKey is! String) return null;
    return VaultDevice(
      id: id,
      uid: uid,
      publicKey: publicKey,
      name: (map['name'] as String?) ?? 'Phone',
      approved: map['approved'] == true,
      addedAt: (map['addedAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// The vault's single settings document: `couples/{cid}/vault/meta`.
@immutable
class VaultMeta {
  const VaultMeta({
    required this.createdBy,
    required this.devices,
    required this.keys,
    required this.verifier,
    this.version = 1,
    this.createdAt,
    this.updatedBy,
    this.updatedAt,
  });

  /// At most this many phones can be registered.
  static const maxDevices = 8;

  final int version;
  final String createdBy;
  final DateTime? createdAt;
  final Map<String, VaultDevice> devices;

  /// The VMK and DK sealed for each approved phone.
  final Map<String, WrappedKeys> keys;

  /// The passcode verifier, encrypted under the VMK.
  final String verifier;
  final String? updatedBy;
  final DateTime? updatedAt;

  /// Phones waiting for approval, oldest first.
  List<VaultDevice> get pending =>
      devices.values.where((d) => !d.approved).toList()..sort(_byAdded);

  /// Every phone, oldest first.
  List<VaultDevice> get sortedDevices =>
      devices.values.toList()..sort(_byAdded);

  static int _byAdded(VaultDevice a, VaultDevice b) {
    final x = a.addedAt;
    final y = b.addedAt;
    if (x == null || y == null) return a.id.compareTo(b.id);
    return x.compareTo(y);
  }

  factory VaultMeta.fromMap(Map<String, dynamic> data) {
    final devices = <String, VaultDevice>{};
    final rawDevices = data['devices'];
    if (rawDevices is Map) {
      rawDevices.forEach((id, value) {
        final device = VaultDevice.fromMap(id as String, value);
        if (device != null) devices[id] = device;
      });
    }
    final keys = <String, WrappedKeys>{};
    final rawKeys = data['keys'];
    if (rawKeys is Map) {
      rawKeys.forEach((id, value) {
        final wrapped = WrappedKeys.fromMap(value);
        if (wrapped != null) keys[id as String] = wrapped;
      });
    }
    return VaultMeta(
      version: (data['version'] as int?) ?? 1,
      createdBy: (data['createdBy'] as String?) ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      devices: devices,
      keys: keys,
      verifier: (data['verifier'] as String?) ?? '',
      updatedBy: data['updatedBy'] as String?,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
