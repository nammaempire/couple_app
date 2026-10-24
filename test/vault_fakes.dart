// Fakes for the vault feature, shared by its tests (and usable by
// screenshot tests): in-memory database, files and keystore, fast
// deterministic crypto, a hand-moved clock, and no camera or biometrics.
import 'dart:async';
import 'dart:typed_data';

import 'package:couple_app/core/backend/backend.dart';
import 'package:couple_app/core/backend/memory_backend.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderListenable;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:couple_app/features/app_lock/data/biometric_auth.dart';
import 'package:couple_app/features/app_lock/providers/app_lock_providers.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/vault/data/device_keystore.dart';
import 'package:couple_app/features/vault/data/device_name.dart';
import 'package:couple_app/features/vault/data/vault_crypto.dart';
import 'package:couple_app/features/vault/data/vault_photo_preparer.dart';
import 'package:couple_app/features/vault/data/vault_service.dart';
import 'package:couple_app/features/vault/models/vault_item.dart';
import 'package:couple_app/features/vault/models/vault_meta.dart';
import 'package:couple_app/features/vault/providers/vault_providers.dart';

const vaultCouple = 'c1';
const asha = 'asha';
const ravi = 'ravi';
const realCode = '246810';
const decoyCode = '135790';

/// Answers the fingerprint prompt with [result].
class FakeVaultBiometrics implements BiometricAuth {
  FakeVaultBiometrics({this.available = true, this.result = true});

  bool available;
  bool result;
  final reasons = <String>[];

  @override
  Future<bool> canAuthenticate() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    reasons.add(reason);
    return result;
  }
}

class FakeDeviceName implements DeviceNameSource {
  const FakeDeviceName(this.name);

  final String name;

  @override
  Future<String> deviceName() async => name;
}

/// A clock the tests move by hand.
class VaultTestClock {
  DateTime now = DateTime(2026, 10, 20, 21, 30);

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}

/// A small real JPEG: a soft diagonal gradient in [from] → [to].
Uint8List gradientJpeg({
  int width = 96,
  int height = 96,
  int from = 0xFFFFB3C7,
  int to = 0xFF6A4FC4,
}) {
  final image = img.Image(width: width, height: height);
  int ch(int c, int shift) => (c >> shift) & 0xFF;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final t = (x + y) / (width + height);
      int mix(int shift) =>
          (ch(from, shift) + (ch(to, shift) - ch(from, shift)) * t).round();
      image.setPixelRgb(x, y, mix(16), mix(8), mix(0));
    }
  }
  return img.encodeJpg(image, quality: 90);
}

/// Skips the camera: [pick] returns [bytes] (or null when [cancel]),
/// [prepare] returns them as both photo and thumbnail.
class FakeVaultPhotoSource implements VaultPhotoSource {
  FakeVaultPhotoSource({Uint8List? bytes}) : bytes = bytes ?? gradientJpeg();

  final Uint8List bytes;
  bool cancel = false;
  final sources = <ImageSource>[];

  @override
  Future<Uint8List?> pick(ImageSource source) async {
    sources.add(source);
    return cancel ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<PreparedPhoto> prepare(Uint8List source) async => PreparedPhoto(
    photo: Uint8List.fromList(bytes),
    thumb: Uint8List.fromList(bytes),
    width: 96,
    height: 96,
  );
}

/// One phone: its keystore, name and crypto (seeded differently per phone).
class VaultTestPhone {
  VaultTestPhone({required this.uid, required this.name, required int seed})
    : keystore = MemoryDeviceKeystore(),
      crypto = VaultCrypto.forTests(seed: seed);

  final String uid;
  final String name;
  final MemoryDeviceKeystore keystore;
  final VaultCrypto crypto;
}

/// Shared backend for one or more phones.
class VaultTestRig {
  VaultTestRig({Db? db})
    : db = db ?? Db(MemoryBackend()),
      blobs = MemoryVaultBlobStore(),
      clock = VaultTestClock(),
      biometrics = FakeVaultBiometrics(),
      photos = FakeVaultPhotoSource() {
    service = VaultService(db: this.db, blobs: blobs);
  }

  final Db db;
  final MemoryVaultBlobStore blobs;
  final VaultTestClock clock;
  final FakeVaultBiometrics biometrics;
  final FakeVaultPhotoSource photos;
  late final VaultService service;

  /// The vault overrides for [phone] (the user, couple and partner are
  /// overridden by each test).
  List<Override> overrides(VaultTestPhone phone) => [
    vaultServiceProvider.overrideWithValue(service),
    deviceKeystoreProvider.overrideWithValue(phone.keystore),
    vaultCryptoProvider.overrideWithValue(phone.crypto),
    vaultClockProvider.overrideWithValue(clock.call),
    deviceNameSourceProvider.overrideWithValue(FakeDeviceName(phone.name)),
    vaultPhotoSourceProvider.overrideWithValue(photos),
    biometricAuthProvider.overrideWithValue(biometrics),
  ];

  /// Sets the vault up as [phone] would, without any UI: [phone] approved,
  /// codes [realCode] and [decoyCode]. Returns the keys and real shelf.
  Future<({VaultKeys keys, String realShelf, DeviceIdentity identity})>
  seedVault(VaultTestPhone phone, {String realShelf = 'a'}) async {
    final crypto = phone.crypto;
    final identity = await identityFor(phone);
    final keys = crypto.newVaultKeys();
    final verifier = await crypto.createVerifier(
      vmk: keys.vmk,
      realCode: realCode,
      decoyCode: decoyCode,
      realShelf: realShelf,
    );
    await service.createVault(
      cid: vaultCouple,
      uid: phone.uid,
      device: VaultDevice(
        id: identity.deviceId,
        uid: phone.uid,
        publicKey: identity.publicKeyB64,
        name: phone.name,
        approved: true,
      ),
      keys: await crypto.wrapKeys(keys, identity.publicKeyB64),
      verifier: verifier,
    );
    return (keys: keys, realShelf: realShelf, identity: identity);
  }

  /// [phone]'s identity, made and stored if it has none.
  Future<DeviceIdentity> identityFor(VaultTestPhone phone) async {
    final existing = await phone.keystore.loadIdentity(phone.uid);
    if (existing != null) return existing;
    final identity = DeviceIdentity(
      deviceId: phone.crypto.newDeviceId(),
      keyPair: await phone.crypto.newDeviceKeyPair(),
    );
    await phone.keystore.saveIdentity(phone.uid, identity);
    return identity;
  }

  /// Registers [phone] and, if [approvedWith] is given, approves it.
  Future<DeviceIdentity> addPhone(
    VaultTestPhone phone, {
    VaultKeys? approvedWith,
  }) async {
    final identity = await identityFor(phone);
    await service.registerDevice(
      cid: vaultCouple,
      device: VaultDevice(
        id: identity.deviceId,
        uid: phone.uid,
        publicKey: identity.publicKeyB64,
        name: phone.name,
        approved: false,
      ),
    );
    if (approvedWith != null) {
      await service.approveDevice(
        cid: vaultCouple,
        uid: phone.uid,
        deviceId: identity.deviceId,
        keys: await phone.crypto.wrapKeys(approvedWith, identity.publicKeyB64),
        approverDeviceName: phone.name,
      );
    }
    return identity;
  }

  /// Adds an encrypted message straight to the database.
  Future<String> seedMessage({
    required VaultCrypto crypto,
    required Uint8List shelfKey,
    required String shelf,
    required String senderId,
    required String text,
    VaultPolicy policy = VaultPolicy.keep,
    DateTime? at,
  }) async {
    final id = service.newItemId(vaultCouple);
    await service.addMessage(
      cid: vaultCouple,
      itemId: id,
      senderId: senderId,
      shelf: shelf,
      ct: await crypto.encryptContent(
        shelfKey,
        id,
        VaultMessageContent(text).toJson(),
      ),
      policy: policy,
      now: at ?? clock.now,
    );
    return id;
  }

  /// Adds an encrypted photo straight to the database and the file store.
  Future<String> seedPhoto({
    required VaultCrypto crypto,
    required Uint8List shelfKey,
    required String shelf,
    required String senderId,
    Uint8List? jpeg,
    VaultPolicy policy = VaultPolicy.keep,
  }) async {
    final bytes = jpeg ?? gradientJpeg();
    final id = service.newItemId(vaultCouple);
    final photoPath = service.newFilePath(vaultCouple);
    final thumbPath = service.newFilePath(vaultCouple);
    await service.addPhoto(
      cid: vaultCouple,
      itemId: id,
      senderId: senderId,
      shelf: shelf,
      ct: await crypto.encryptContent(
        shelfKey,
        id,
        VaultPhotoContent(
          width: 96,
          height: 96,
          photoPath: photoPath,
          thumbPath: thumbPath,
          bytes: bytes.length,
        ).toJson(),
      ),
      policy: policy,
      photoPath: photoPath,
      photo: await crypto.encryptBlob(shelfKey, id, 'photo', bytes),
      thumbPath: thumbPath,
      thumb: await crypto.encryptBlob(shelfKey, id, 'thumb', bytes),
      now: clock.now,
    );
    return id;
  }
}

/// Lets in-memory database streams and async loads settle outside widget tests.
Future<void> settleAsync([int rounds = 20]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Keeps a provider alive in a container for the length of a test.
void keepAlive(
  ProviderContainer container,
  List<ProviderListenable<Object?>> providers,
) {
  for (final p in providers) {
    container.listen(p, (_, _) {});
  }
}

/// A paired profile. Adults by default (born 1996).
AppUser vaultUser(
  String uid, {
  DateTime? birthday,
  bool noBirthday = false,
  DateTime? adultConfirmedAt,
}) => AppUser(
  uid: uid,
  displayName: uid == asha ? 'Asha' : 'Ravi',
  coupleId: vaultCouple,
  birthday: noBirthday ? null : birthday ?? DateTime(1996, 3, 8),
  adultConfirmedAt: adultConfirmedAt,
);

/// The signed-in user, the couple and the partner.
List<Override> vaultPeopleOverrides({
  required AppUser me,
  required AppUser? partner,
}) => [
  currentUserProvider.overrideWithBuild((ref, _) => me),
  coupleProvider.overrideWith(
    (ref) => Stream.value(
      const Couple(
        id: vaultCouple,
        inviteCode: 'K7MP3Q',
        memberIds: [asha, ravi],
      ),
    ),
  ),
  partnerProvider.overrideWith(
    (ref) => partner == null ? const Stream.empty() : Stream.value(partner),
  ),
];
