import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// The vault's end-to-end encryption, in pure Dart.
///
/// - Each phone has an X25519 key pair; its private key never leaves the
///   phone.
/// - The Vault Master Key (VMK) and the Decoy Key (DK) are 32 random bytes,
///   sealed for each approved phone with an ephemeral X25519 key, HKDF-SHA256
///   and AES-GCM-256 ([wrapKey]).
/// - The passcode verifier holds Argon2id hashes of the real and decoy codes
///   and which shelf is real, encrypted under the VMK ([createVerifier]).
/// - Each item has its own AES-GCM key, HKDF(shelf key, item id)
///   ([encryptContent], [encryptBlob]).
///
/// Randomness and the worker that runs slow steps (Argon2id, large photos)
/// are injected, so tests are deterministic and fast.

/// Runs a slow, self-contained task. Production runs it on another isolate;
/// tests run it inline.
typedef VaultWorker = Future<R> Function<R>(FutureOr<R> Function() task);

/// Runs [task] on a fresh isolate, so the UI keeps drawing.
Future<R> isolateWorker<R>(FutureOr<R> Function() task) => Isolate.run(task);

/// Runs [task] on this isolate (tests).
Future<R> inlineWorker<R>(FutureOr<R> Function() task) async => task();

/// Thrown when something can't be decrypted: the wrong key, or data that
/// was changed.
class VaultCryptoException implements Exception {
  const VaultCryptoException(this.message);
  final String message;
  @override
  String toString() => 'VaultCryptoException: $message';
}

/// Argon2id cost. [phone] is what the app uses; tests inject tiny values.
class Argon2Params {
  const Argon2Params({
    required this.memoryKib,
    required this.iterations,
    required this.parallelism,
  });

  /// 19 MiB, 2 passes, 1 lane: the OWASP minimum, well under a second on a
  /// mid-range phone.
  static const phone = Argon2Params(
    memoryKib: 19456,
    iterations: 2,
    parallelism: 1,
  );

  final int memoryKib;
  final int iterations;
  final int parallelism;

  Map<String, dynamic> toJson() => {
    'm': memoryKib,
    't': iterations,
    'p': parallelism,
  };

  factory Argon2Params.fromJson(Map<String, dynamic> json) => Argon2Params(
    memoryKib: json['m'] as int,
    iterations: json['t'] as int,
    parallelism: json['p'] as int,
  );

  @override
  bool operator ==(Object other) =>
      other is Argon2Params &&
      other.memoryKib == memoryKib &&
      other.iterations == iterations &&
      other.parallelism == parallelism;

  @override
  int get hashCode => Object.hash(memoryKib, iterations, parallelism);
}

/// This phone's X25519 key pair. [privateKey] is the 32-byte seed.
class DeviceKeyPair {
  const DeviceKeyPair({required this.privateKey, required this.publicKey});

  final Uint8List privateKey;
  final Uint8List publicKey;

  String get publicKeyB64 => base64Encode(publicKey);
}

/// The two shelf keys, in memory only while the vault is open.
class VaultKeys {
  VaultKeys({required this.vmk, required this.dk});

  final Uint8List vmk;
  final Uint8List dk;

  /// Overwrites both keys with zeros (best effort; Dart may have copies).
  void wipe() {
    vmk.fillRange(0, vmk.length, 0);
    dk.fillRange(0, dk.length, 0);
  }
}

/// The VMK and DK sealed for one phone: `keys.{deviceId}` in the vault meta.
class WrappedKeys {
  const WrappedKeys({required this.vmk, required this.dk});

  final String vmk;
  final String dk;

  Map<String, dynamic> toMap() => {'vmk': vmk, 'dk': dk};

  static WrappedKeys? fromMap(Object? map) {
    if (map is! Map) return null;
    final vmk = map['vmk'];
    final dk = map['dk'];
    if (vmk is! String || dk is! String) return null;
    return WrappedKeys(vmk: vmk, dk: dk);
  }
}

/// Which code was entered.
enum CodeMatch { real, decoy, none }

/// The decrypted passcode verifier.
class VerifierPayload {
  const VerifierPayload({
    required this.realShelf,
    required this.realSalt,
    required this.realHash,
    required this.decoySalt,
    required this.decoyHash,
    required this.params,
  });

  /// `'a'` or `'b'`: the shelf the real code opens. The other one is the
  /// decoy. Only ever stored encrypted.
  final String realShelf;
  final Uint8List realSalt;
  final Uint8List realHash;
  final Uint8List decoySalt;
  final Uint8List decoyHash;
  final Argon2Params params;

  String get decoyShelf => realShelf == 'a' ? 'b' : 'a';

  Map<String, dynamic> toJson() => {
    'v': 1,
    'shelf': realShelf,
    'real': base64Encode(realHash),
    'realSalt': base64Encode(realSalt),
    'decoy': base64Encode(decoyHash),
    'decoySalt': base64Encode(decoySalt),
    'argon2': params.toJson(),
  };

  factory VerifierPayload.fromJson(Map<String, dynamic> json) =>
      VerifierPayload(
        realShelf: json['shelf'] as String,
        realHash: base64Decode(json['real'] as String),
        realSalt: base64Decode(json['realSalt'] as String),
        decoyHash: base64Decode(json['decoy'] as String),
        decoySalt: base64Decode(json['decoySalt'] as String),
        params: Argon2Params.fromJson(
          (json['argon2'] as Map).cast<String, dynamic>(),
        ),
      );
}

/// Whether [code] is six digits.
bool isValidVaultCode(String code) => RegExp(r'^\d{6}$').hasMatch(code);

/// Compares without stopping at the first difference.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// A short safety code for a phone's public key, shown on both phones when
/// one approves the other: four groups of four digits.
String deviceFingerprint(String publicKeyB64) {
  final hash = const DartSha256().hashSync(base64Decode(publicKeyB64)).bytes;
  return [
    for (var i = 0; i < 4; i++)
      (((hash[2 * i] << 8) | hash[2 * i + 1]) % 10000).toString().padLeft(
        4,
        '0',
      ),
  ].join(' ');
}

/// Argon2id of [code] with [salt]: 32 bytes. Top level so it can run on
/// another isolate.
Future<Uint8List> argon2idHash(
  String code,
  Uint8List salt,
  Argon2Params params,
) async {
  final algorithm = DartArgon2id(
    memory: params.memoryKib,
    iterations: params.iterations,
    parallelism: params.parallelism,
    hashLength: 32,
    // The caller decides where this runs.
    maxIsolates: 0,
  );
  final key = await algorithm.deriveKey(
    secretKey: SecretKey(utf8.encode(code)),
    nonce: salt,
  );
  return Uint8List.fromList(await key.extractBytes());
}

/// Hashes [code] against both entries of [payload] (always both, so the
/// time taken doesn't say which matched) and compares in constant time.
Future<CodeMatch> _matchCode(
  String code,
  Uint8List realSalt,
  Uint8List realHash,
  Uint8List decoySalt,
  Uint8List decoyHash,
  Argon2Params params,
) async {
  final real = await argon2idHash(code, realSalt, params);
  final decoy = await argon2idHash(code, decoySalt, params);
  final isReal = constantTimeEquals(real, realHash);
  final isDecoy = constantTimeEquals(decoy, decoyHash);
  if (isReal) return CodeMatch.real;
  if (isDecoy) return CodeMatch.decoy;
  return CodeMatch.none;
}

final _gcm = DartAesGcm.with256bits();
const _nonceLength = 12;
const _macLength = 16;

/// AES-GCM-256 with [nonce]: returns nonce ‖ ciphertext ‖ mac.
Uint8List _seal(
  Uint8List key,
  Uint8List nonce,
  List<int> clear, {
  required List<int> aad,
}) {
  final box = _gcm.encryptSync(
    clear,
    secretKeyData: SecretKeyData(key),
    nonce: nonce,
    aad: aad,
  );
  final out = Uint8List(_nonceLength + box.cipherText.length + _macLength);
  out.setRange(0, _nonceLength, nonce);
  out.setRange(
    _nonceLength,
    _nonceLength + box.cipherText.length,
    box.cipherText,
  );
  out.setRange(out.length - _macLength, out.length, box.mac.bytes);
  return out;
}

/// Opens what [_seal] made, checking the mac.
Uint8List _open(Uint8List key, Uint8List sealed, {required List<int> aad}) {
  if (sealed.length < _nonceLength + _macLength) {
    throw const VaultCryptoException('Too short');
  }
  final box = SecretBox(
    Uint8List.sublistView(sealed, _nonceLength, sealed.length - _macLength),
    nonce: Uint8List.sublistView(sealed, 0, _nonceLength),
    mac: Mac(Uint8List.sublistView(sealed, sealed.length - _macLength)),
  );
  try {
    return Uint8List.fromList(
      _gcm.decryptSync(box, secretKeyData: SecretKeyData(key), aad: aad),
    );
  } on SecretBoxAuthenticationError {
    throw const VaultCryptoException('Authentication failed');
  }
}

/// The vault's crypto operations. See the library comment.
class VaultCrypto {
  VaultCrypto({
    Random? random,
    this.argon2 = Argon2Params.phone,
    VaultWorker? worker,
    this.offloadAbove = 256 * 1024,
  }) : _random = random ?? Random.secure(),
       _worker = worker ?? isolateWorker;

  /// A deterministic instance for tests: seeded randomness, cheap Argon2id
  /// and everything on this isolate.
  factory VaultCrypto.forTests({
    int seed = 42,
    Argon2Params argon2 = const Argon2Params(
      memoryKib: 64,
      iterations: 1,
      parallelism: 1,
    ),
  }) => VaultCrypto(random: Random(seed), argon2: argon2, worker: inlineWorker);

  final Random _random;
  final VaultWorker _worker;

  /// Cost for new verifiers. Checking a code uses the cost stored in the
  /// verifier, so it can be raised later without locking anyone out.
  final Argon2Params argon2;

  /// Blobs larger than this are encrypted and decrypted on the worker.
  final int offloadAbove;

  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static const _x25519 = DartX25519();

  Uint8List randomBytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  /// A random id for this phone: 20 hex characters.
  String newDeviceId() {
    final bytes = randomBytes(10);
    return [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
  }

  /// `'a'` or `'b'`, at random.
  String randomShelf() => _random.nextBool() ? 'a' : 'b';

  Future<DeviceKeyPair> newDeviceKeyPair() async {
    final pair = await _x25519.newKeyPairFromSeed(randomBytes(32));
    final data = await pair.extract();
    return DeviceKeyPair(
      privateKey: Uint8List.fromList(data.bytes),
      publicKey: Uint8List.fromList(data.publicKey.bytes),
    );
  }

  /// A fresh VMK and DK.
  VaultKeys newVaultKeys() =>
      VaultKeys(vmk: randomBytes(32), dk: randomBytes(32));

  static Future<Uint8List> _hkdfBytes(
    List<int> secret, {
    required List<int> salt,
    required String info,
  }) async {
    final key = await _hkdf.deriveKey(
      secretKey: SecretKey(secret),
      nonce: salt,
      info: utf8.encode(info),
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  // ---- Sealing keys for a phone ------------------------------------------

  /// Seals [key] so only the holder of [recipientPublicKeyB64]'s private key
  /// can open it: base64(epk ‖ nonce ‖ ciphertext ‖ mac).
  Future<String> wrapKey(Uint8List key, String recipientPublicKeyB64) async {
    final recipient = base64Decode(recipientPublicKeyB64);
    final ephemeral = await _x25519.newKeyPairFromSeed(randomBytes(32));
    final epk = Uint8List.fromList((await ephemeral.extractPublicKey()).bytes);
    final shared = await _x25519.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: SimplePublicKey(recipient, type: KeyPairType.x25519),
    );
    final wrapKey = await _hkdfBytes(
      await shared.extractBytes(),
      salt: [...epk, ...recipient],
      info: 'us-vault/wrap/v1',
    );
    final sealed = _seal(wrapKey, randomBytes(_nonceLength), key, aad: epk);
    return base64Encode([...epk, ...sealed]);
  }

  /// Opens what [wrapKey] sealed for [device]. Throws
  /// [VaultCryptoException] if it was sealed for another phone or changed.
  Future<Uint8List> unwrapKey(String wrapped, DeviceKeyPair device) async {
    final Uint8List bytes;
    try {
      bytes = base64Decode(wrapped);
    } on FormatException {
      throw const VaultCryptoException('Not base64');
    }
    if (bytes.length < 32 + _nonceLength + _macLength) {
      throw const VaultCryptoException('Too short');
    }
    final epk = Uint8List.sublistView(bytes, 0, 32);
    final pair = await _x25519.newKeyPairFromSeed(device.privateKey);
    final shared = await _x25519.sharedSecretKey(
      keyPair: pair,
      remotePublicKey: SimplePublicKey(epk, type: KeyPairType.x25519),
    );
    final wrapKey = await _hkdfBytes(
      await shared.extractBytes(),
      salt: [...epk, ...device.publicKey],
      info: 'us-vault/wrap/v1',
    );
    return _open(wrapKey, Uint8List.sublistView(bytes, 32), aad: epk);
  }

  Future<WrappedKeys> wrapKeys(VaultKeys keys, String publicKeyB64) async =>
      WrappedKeys(
        vmk: await wrapKey(keys.vmk, publicKeyB64),
        dk: await wrapKey(keys.dk, publicKeyB64),
      );

  Future<VaultKeys> unwrapKeys(
    WrappedKeys wrapped,
    DeviceKeyPair device,
  ) async => VaultKeys(
    vmk: await unwrapKey(wrapped.vmk, device),
    dk: await unwrapKey(wrapped.dk, device),
  );

  // ---- Passcode verifier --------------------------------------------------

  Future<Uint8List> _verifierKey(Uint8List vmk) =>
      _hkdfBytes(vmk, salt: const [], info: 'us-vault/verifier/v1');

  /// Hashes both codes with fresh salts and [argon2], and encrypts them with
  /// the real shelf's name under [vmk]. [realShelf] is random when omitted.
  Future<String> createVerifier({
    required Uint8List vmk,
    required String realCode,
    required String decoyCode,
    String? realShelf,
  }) async {
    final payload = await buildVerifier(
      realCode: realCode,
      decoyCode: decoyCode,
      realShelf: realShelf ?? randomShelf(),
    );
    return sealVerifier(vmk, payload);
  }

  /// A new payload with both codes hashed.
  Future<VerifierPayload> buildVerifier({
    required String realCode,
    required String decoyCode,
    required String realShelf,
  }) async {
    final realSalt = randomBytes(16);
    final decoySalt = randomBytes(16);
    final params = argon2;
    final hashes = await _hashPairOn(
      _worker,
      realCode,
      realSalt,
      decoyCode,
      decoySalt,
      params,
    );
    return VerifierPayload(
      realShelf: realShelf,
      realSalt: realSalt,
      realHash: hashes[0],
      decoySalt: decoySalt,
      decoyHash: hashes[1],
      params: params,
    );
  }

  /// [payload] with one code replaced (new salt, current [argon2] cost).
  Future<VerifierPayload> replaceCode(
    VerifierPayload payload, {
    String? realCode,
    String? decoyCode,
  }) async {
    var next = payload;
    final params = argon2;
    if (realCode != null) {
      final salt = randomBytes(16);
      final hash = await _hashOn(_worker, realCode, salt, params);
      next = VerifierPayload(
        realShelf: next.realShelf,
        realSalt: salt,
        realHash: hash,
        decoySalt: next.decoySalt,
        decoyHash: next.decoyHash,
        params: params,
      );
    }
    if (decoyCode != null) {
      final salt = randomBytes(16);
      final hash = await _hashOn(_worker, decoyCode, salt, params);
      next = VerifierPayload(
        realShelf: next.realShelf,
        realSalt: next.realSalt,
        realHash: next.realHash,
        decoySalt: salt,
        decoyHash: hash,
        params: params,
      );
    }
    return next;
  }

  Future<String> sealVerifier(Uint8List vmk, VerifierPayload payload) async {
    final key = await _verifierKey(vmk);
    final clear = utf8.encode(jsonEncode(payload.toJson()));
    return base64Encode(
      _seal(key, randomBytes(_nonceLength), clear, aad: _verifierAad),
    );
  }

  static final _verifierAad = utf8.encode('us-vault/verifier');

  Future<VerifierPayload> openVerifier(String verifier, Uint8List vmk) async {
    final key = await _verifierKey(vmk);
    final clear = _open(key, base64Decode(verifier), aad: _verifierAad);
    return VerifierPayload.fromJson(
      (jsonDecode(utf8.decode(clear)) as Map).cast<String, dynamic>(),
    );
  }

  /// Which code [code] is, using the cost stored in [payload].
  Future<CodeMatch> checkCode(VerifierPayload payload, String code) {
    return _matchOn(
      _worker,
      code,
      payload.realSalt,
      payload.realHash,
      payload.decoySalt,
      payload.decoyHash,
      payload.params,
    );
  }

  // ---- Items ---------------------------------------------------------------

  /// The per-item key: HKDF-SHA256(shelf key, item id).
  Future<Uint8List> itemKey(Uint8List shelfKey, String itemId) =>
      _hkdfBytes(shelfKey, salt: utf8.encode(itemId), info: 'us-vault/item/v1');

  /// Encrypts an item's content JSON: base64(nonce ‖ ciphertext ‖ mac).
  Future<String> encryptContent(
    Uint8List shelfKey,
    String itemId,
    Map<String, dynamic> content,
  ) async {
    final key = await itemKey(shelfKey, itemId);
    final sealed = _seal(
      key,
      randomBytes(_nonceLength),
      utf8.encode(jsonEncode(content)),
      aad: utf8.encode('ct:$itemId'),
    );
    return base64Encode(sealed);
  }

  Future<Map<String, dynamic>> decryptContent(
    Uint8List shelfKey,
    String itemId,
    String ct,
  ) async {
    final key = await itemKey(shelfKey, itemId);
    final Uint8List sealed;
    try {
      sealed = base64Decode(ct);
    } on FormatException {
      throw const VaultCryptoException('Not base64');
    }
    final clear = _open(key, sealed, aad: utf8.encode('ct:$itemId'));
    return (jsonDecode(utf8.decode(clear)) as Map).cast<String, dynamic>();
  }

  /// Encrypts photo or thumbnail bytes. [purpose] (`photo`, `thumb`) is
  /// bound in, so the two files can't be swapped.
  Future<Uint8List> encryptBlob(
    Uint8List shelfKey,
    String itemId,
    String purpose,
    Uint8List bytes,
  ) async {
    final key = await itemKey(shelfKey, itemId);
    final nonce = randomBytes(_nonceLength);
    final aad = utf8.encode('$purpose:$itemId');
    if (bytes.length <= offloadAbove) {
      return _seal(key, nonce, bytes, aad: aad);
    }
    return _sealOn(_worker, key, nonce, bytes, aad);
  }

  Future<Uint8List> decryptBlob(
    Uint8List shelfKey,
    String itemId,
    String purpose,
    Uint8List sealed,
  ) async {
    final key = await itemKey(shelfKey, itemId);
    final aad = utf8.encode('$purpose:$itemId');
    if (sealed.length <= offloadAbove) return _open(key, sealed, aad: aad);
    return _openOn(_worker, key, sealed, aad);
  }
}

Future<List<Uint8List>> _hashPair(
  String realCode,
  Uint8List realSalt,
  String decoyCode,
  Uint8List decoySalt,
  Argon2Params params,
) async => [
  await argon2idHash(realCode, realSalt, params),
  await argon2idHash(decoyCode, decoySalt, params),
];

// Closures for the worker are made in these plain (not async) functions, so
// they capture only their arguments and can be sent to another isolate.

Future<Uint8List> _hashOn(
  VaultWorker worker,
  String code,
  Uint8List salt,
  Argon2Params params,
) => worker(() => argon2idHash(code, salt, params));

Future<List<Uint8List>> _hashPairOn(
  VaultWorker worker,
  String realCode,
  Uint8List realSalt,
  String decoyCode,
  Uint8List decoySalt,
  Argon2Params params,
) => worker(() => _hashPair(realCode, realSalt, decoyCode, decoySalt, params));

Future<CodeMatch> _matchOn(
  VaultWorker worker,
  String code,
  Uint8List realSalt,
  Uint8List realHash,
  Uint8List decoySalt,
  Uint8List decoyHash,
  Argon2Params params,
) => worker(
  () => _matchCode(code, realSalt, realHash, decoySalt, decoyHash, params),
);

Future<Uint8List> _sealOn(
  VaultWorker worker,
  Uint8List key,
  Uint8List nonce,
  Uint8List bytes,
  List<int> aad,
) => worker(() => _seal(key, nonce, bytes, aad: aad));

Future<Uint8List> _openOn(
  VaultWorker worker,
  Uint8List key,
  Uint8List sealed,
  List<int> aad,
) => worker(() => _open(key, sealed, aad: aad));
