import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:couple_app/features/vault/data/vault_crypto.dart';

/// This phone's vault identity: a random device id and its X25519 key pair.
@immutable
class DeviceIdentity {
  const DeviceIdentity({required this.deviceId, required this.keyPair});

  final String deviceId;
  final DeviceKeyPair keyPair;

  String get publicKeyB64 => keyPair.publicKeyB64;

  String toJson() => jsonEncode({
    'id': deviceId,
    'sk': base64Encode(keyPair.privateKey),
    'pk': base64Encode(keyPair.publicKey),
  });

  factory DeviceIdentity.fromJson(String json) {
    final map = (jsonDecode(json) as Map).cast<String, dynamic>();
    return DeviceIdentity(
      deviceId: map['id'] as String,
      keyPair: DeviceKeyPair(
        privateKey: base64Decode(map['sk'] as String),
        publicKey: base64Decode(map['pk'] as String),
      ),
    );
  }
}

/// What this phone remembers about the vault, besides its key: wrong-code
/// attempts, the cooldown, and the fingerprint / face choice.
@immutable
class VaultLocalState {
  const VaultLocalState({
    this.failedAttempts = 0,
    this.cooldownUntil,
    this.biometric = false,
    this.biometricAsked = false,
  });

  /// Wrong codes in a row since the last unlock.
  final int failedAttempts;

  /// No codes are accepted before this.
  final DateTime? cooldownUntil;

  /// Unlock with fingerprint or face on this phone.
  final bool biometric;

  /// The fingerprint / face question has been asked on this phone.
  final bool biometricAsked;

  VaultLocalState copyWith({
    int? failedAttempts,
    DateTime? Function()? cooldownUntil,
    bool? biometric,
    bool? biometricAsked,
  }) => VaultLocalState(
    failedAttempts: failedAttempts ?? this.failedAttempts,
    cooldownUntil: cooldownUntil == null ? this.cooldownUntil : cooldownUntil(),
    biometric: biometric ?? this.biometric,
    biometricAsked: biometricAsked ?? this.biometricAsked,
  );

  String toJson() => jsonEncode({
    'failed': failedAttempts,
    'cooldownUntil': cooldownUntil?.millisecondsSinceEpoch,
    'biometric': biometric,
    'biometricAsked': biometricAsked,
  });

  factory VaultLocalState.fromJson(String json) {
    final map = (jsonDecode(json) as Map).cast<String, dynamic>();
    final until = map['cooldownUntil'] as int?;
    return VaultLocalState(
      failedAttempts: (map['failed'] as int?) ?? 0,
      cooldownUntil: until == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(until),
      biometric: (map['biometric'] as bool?) ?? false,
      biometricAsked: (map['biometricAsked'] as bool?) ?? false,
    );
  }
}

/// Keeps the vault's per-phone secrets. Everything is per account ([uid]),
/// so a second account on the same phone starts fresh.
///
/// Behind an interface so tests can use [MemoryDeviceKeystore].
abstract class DeviceKeystore {
  /// This phone's identity, or null if it has none yet (or it can't be read,
  /// e.g. after a restore to a new phone).
  Future<DeviceIdentity?> loadIdentity(String uid);

  Future<void> saveIdentity(String uid, DeviceIdentity identity);

  Future<void> clearIdentity(String uid);

  Future<VaultLocalState> loadState(String uid);

  Future<void> saveState(String uid, VaultLocalState state);
}

/// [DeviceKeystore] in the Android keystore-backed encrypted preferences,
/// through flutter_secure_storage.
class SecureDeviceKeystore implements DeviceKeystore {
  SecureDeviceKeystore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _identityKey(String uid) => 'vault.$uid.identity';
  static String _stateKey(String uid) => 'vault.$uid.state';

  @override
  Future<DeviceIdentity?> loadIdentity(String uid) async {
    try {
      final json = await _storage.read(key: _identityKey(uid));
      return json == null ? null : DeviceIdentity.fromJson(json);
    } catch (e) {
      // The keystore key is gone (restored backup, cleared credentials):
      // start again as a new phone.
      debugPrint('vault: identity unreadable: $e');
      await _deleteQuietly(_identityKey(uid));
      return null;
    }
  }

  @override
  Future<void> saveIdentity(String uid, DeviceIdentity identity) =>
      _storage.write(key: _identityKey(uid), value: identity.toJson());

  @override
  Future<void> clearIdentity(String uid) => _deleteQuietly(_identityKey(uid));

  @override
  Future<VaultLocalState> loadState(String uid) async {
    try {
      final json = await _storage.read(key: _stateKey(uid));
      return json == null
          ? const VaultLocalState()
          : VaultLocalState.fromJson(json);
    } catch (e) {
      debugPrint('vault: local state unreadable: $e');
      return const VaultLocalState();
    }
  }

  @override
  Future<void> saveState(String uid, VaultLocalState state) =>
      _storage.write(key: _stateKey(uid), value: state.toJson());

  Future<void> _deleteQuietly(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }
}

/// [DeviceKeystore] in memory only: for tests and previews.
class MemoryDeviceKeystore implements DeviceKeystore {
  MemoryDeviceKeystore({
    Map<String, DeviceIdentity>? identities,
    Map<String, VaultLocalState>? states,
  }) : identities = identities ?? {},
       states = states ?? {};

  final Map<String, DeviceIdentity> identities;
  final Map<String, VaultLocalState> states;

  @override
  Future<DeviceIdentity?> loadIdentity(String uid) async => identities[uid];

  @override
  Future<void> saveIdentity(String uid, DeviceIdentity identity) async =>
      identities[uid] = identity;

  @override
  Future<void> clearIdentity(String uid) async => identities.remove(uid);

  @override
  Future<VaultLocalState> loadState(String uid) async =>
      states[uid] ?? const VaultLocalState();

  @override
  Future<void> saveState(String uid, VaultLocalState state) async =>
      states[uid] = state;
}
