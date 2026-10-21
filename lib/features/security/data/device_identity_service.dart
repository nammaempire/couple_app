import 'package:couple_app/features/security/models/known_device.dart';
import 'package:couple_app/features/vault/data/device_keystore.dart';
import 'package:couple_app/features/vault/data/device_name.dart';
import 'package:couple_app/features/vault/data/vault_crypto.dart';

/// Who this phone is, shared by sign-in protection and the private vault:
/// one random device id per account in secure storage (the vault's
/// identity, made here if the vault hasn't made it yet), and the phone's
/// model name from the `couple_app/device_info` channel.
///
/// Secure storage doesn't survive a reinstall, so a reinstalled app is a
/// new phone with a new id.
class DeviceIdentityService {
  DeviceIdentityService({
    required this.keystore,
    required this.crypto,
    required this.names,
  });

  /// Where the id lives (the vault's per-account identity).
  final DeviceKeystore keystore;

  /// Makes a new id and key pair.
  final VaultCrypto crypto;

  /// The phone's model name.
  final DeviceNameSource names;

  final _loading = <String, Future<DeviceIdentity>>{};
  String? _name;

  /// This phone's identity for [uid], made and saved the first time. Calls
  /// at the same time share one load, so the id is only ever made once.
  Future<DeviceIdentity> identity(String uid) {
    final pending = _loading[uid];
    if (pending != null) return pending;
    final future = _loadOrCreate(uid).whenComplete(() {
      // A block: returning the removed future would wait on itself.
      _loading.remove(uid);
    });
    _loading[uid] = future;
    return future;
  }

  /// This phone's id for [uid].
  Future<String> deviceId(String uid) async => (await identity(uid)).deviceId;

  /// This phone's model, e.g. "Pixel 9", at most 60 characters.
  Future<String> deviceName() async =>
      _name ??= KnownDevice.clampName(await names.deviceName());

  Future<DeviceIdentity> _loadOrCreate(String uid) async {
    final existing = await keystore.loadIdentity(uid);
    if (existing != null) return existing;
    final identity = DeviceIdentity(
      deviceId: crypto.newDeviceId(),
      keyPair: await crypto.newDeviceKeyPair(),
    );
    await keystore.saveIdentity(uid, identity);
    return identity;
  }
}
