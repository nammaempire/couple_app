import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/vault/data/vault_crypto.dart';

/// The vault's crypto, with seeded randomness and cheap Argon2id.
void main() {
  late VaultCrypto crypto;

  setUp(() => crypto = VaultCrypto.forTests());

  group('sealing keys for a phone', () {
    test('wrap then unwrap gives the key back', () async {
      final phone = await crypto.newDeviceKeyPair();
      final key = crypto.randomBytes(32);
      final wrapped = await crypto.wrapKey(key, phone.publicKeyB64);
      expect(await crypto.unwrapKey(wrapped, phone), key);
      // One string: epk 32 + nonce 12 + key 32 + mac 16 bytes.
      expect(base64Decode(wrapped), hasLength(92));
      expect(wrapped.length, lessThanOrEqualTo(400));
    });

    test('another phone\'s key cannot unwrap it', () async {
      final asha = await crypto.newDeviceKeyPair();
      final ravi = await crypto.newDeviceKeyPair();
      final wrapped = await crypto.wrapKey(
        crypto.randomBytes(32),
        asha.publicKeyB64,
      );
      expect(
        () => crypto.unwrapKey(wrapped, ravi),
        throwsA(isA<VaultCryptoException>()),
      );
    });

    test('both shelf keys round-trip', () async {
      final phone = await crypto.newDeviceKeyPair();
      final keys = crypto.newVaultKeys();
      final wrapped = await crypto.wrapKeys(keys, phone.publicKeyB64);
      final back = await crypto.unwrapKeys(wrapped, phone);
      expect(back.vmk, keys.vmk);
      expect(back.dk, keys.dk);
      expect(keys.vmk, isNot(keys.dk));
    });

    test('a tampered wrap is refused', () async {
      final phone = await crypto.newDeviceKeyPair();
      final wrapped = base64Decode(
        await crypto.wrapKey(crypto.randomBytes(32), phone.publicKeyB64),
      );
      wrapped[50] ^= 1;
      expect(
        () => crypto.unwrapKey(base64Encode(wrapped), phone),
        throwsA(isA<VaultCryptoException>()),
      );
    });

    test('randomness is injected: same seed, same output', () async {
      final a = VaultCrypto.forTests(seed: 7);
      final b = VaultCrypto.forTests(seed: 7);
      expect(a.newDeviceId(), b.newDeviceId());
      expect(
        (await a.newDeviceKeyPair()).publicKey,
        (await b.newDeviceKeyPair()).publicKey,
      );
      expect(a.newDeviceId(), hasLength(20));
    });

    test('fingerprints are four groups of four digits, stable', () async {
      final phone = await crypto.newDeviceKeyPair();
      final print = deviceFingerprint(phone.publicKeyB64);
      expect(print, matches(RegExp(r'^\d{4} \d{4} \d{4} \d{4}$')));
      expect(deviceFingerprint(phone.publicKeyB64), print);
      final other = await crypto.newDeviceKeyPair();
      expect(deviceFingerprint(other.publicKeyB64), isNot(print));
    });
  });

  group('AES-GCM items', () {
    test('content round-trips and is bound to its item', () async {
      final key = crypto.randomBytes(32);
      final ct = await crypto.encryptContent(key, 'item1', {'text': 'hi'});
      expect(await crypto.decryptContent(key, 'item1', ct), {'text': 'hi'});
      expect(ct, isNot(contains('hi')));
      // Moved to another item id: refused.
      expect(
        () => crypto.decryptContent(key, 'item2', ct),
        throwsA(isA<VaultCryptoException>()),
      );
    });

    test('any changed byte is detected', () async {
      final key = crypto.randomBytes(32);
      final ct = base64Decode(
        await crypto.encryptContent(key, 'i', {'text': 'secret'}),
      );
      for (final index in [0, 13, ct.length - 1]) {
        final tampered = Uint8List.fromList(ct)..[index] ^= 0x01;
        expect(
          () => crypto.decryptContent(key, 'i', base64Encode(tampered)),
          throwsA(isA<VaultCryptoException>()),
          reason: 'byte $index',
        );
      }
    });

    test('the wrong shelf key is refused', () async {
      final vmk = crypto.randomBytes(32);
      final dk = crypto.randomBytes(32);
      final ct = await crypto.encryptContent(vmk, 'i', {'text': 'x'});
      expect(
        () => crypto.decryptContent(dk, 'i', ct),
        throwsA(isA<VaultCryptoException>()),
      );
    });

    test('photo and thumbnail blobs round-trip and cannot swap', () async {
      final key = crypto.randomBytes(32);
      final bytes = Uint8List.fromList(List.generate(5000, (i) => i % 251));
      final sealed = await crypto.encryptBlob(key, 'p1', 'photo', bytes);
      expect(sealed.length, bytes.length + 28);
      expect(await crypto.decryptBlob(key, 'p1', 'photo', sealed), bytes);
      expect(
        () => crypto.decryptBlob(key, 'p1', 'thumb', sealed),
        throwsA(isA<VaultCryptoException>()),
      );
    });

    test('large blobs go through the worker', () async {
      var ran = 0;
      Future<R> counting<R>(FutureOr<R> Function() task) async {
        ran++;
        return task();
      }

      final c = VaultCrypto(worker: counting, offloadAbove: 100);
      final key = c.randomBytes(32);
      final sealed = await c.encryptBlob(key, 'i', 'photo', Uint8List(500));
      await c.decryptBlob(key, 'i', 'photo', sealed);
      expect(ran, 2);
    });
  });

  group('passcode verifier', () {
    late Uint8List vmk;
    late String verifier;

    setUp(() async {
      vmk = crypto.randomBytes(32);
      verifier = await crypto.createVerifier(
        vmk: vmk,
        realCode: '123456',
        decoyCode: '654321',
        realShelf: 'b',
      );
    });

    test('real, decoy and wrong codes', () async {
      final payload = await crypto.openVerifier(verifier, vmk);
      expect(await crypto.checkCode(payload, '123456'), CodeMatch.real);
      expect(await crypto.checkCode(payload, '654321'), CodeMatch.decoy);
      expect(await crypto.checkCode(payload, '000000'), CodeMatch.none);
      expect(payload.realShelf, 'b');
      expect(payload.decoyShelf, 'a');
    });

    test('is unreadable without the VMK, and hides the shelves', () async {
      expect(
        () => crypto.openVerifier(verifier, crypto.randomBytes(32)),
        throwsA(isA<VaultCryptoException>()),
      );
      final raw = utf8.decode(base64Decode(verifier), allowMalformed: true);
      expect(raw, isNot(contains('shelf')));
      expect(verifier.length, lessThanOrEqualTo(4000));
    });

    test('the shelf is random when not given', () async {
      final shelves = <String>{};
      for (var i = 0; i < 12; i++) {
        final v = await crypto.createVerifier(
          vmk: vmk,
          realCode: '111111',
          decoyCode: '222222',
        );
        shelves.add((await crypto.openVerifier(v, vmk)).realShelf);
      }
      expect(shelves, {'a', 'b'});
    });

    test('replacing one code keeps the other', () async {
      final payload = await crypto.openVerifier(verifier, vmk);
      final next = await crypto.replaceCode(payload, realCode: '999999');
      expect(await crypto.checkCode(next, '999999'), CodeMatch.real);
      expect(await crypto.checkCode(next, '123456'), CodeMatch.none);
      expect(await crypto.checkCode(next, '654321'), CodeMatch.decoy);
      expect(next.realShelf, payload.realShelf);
    });

    test('Argon2id parameters are recorded and respected', () async {
      const params = Argon2Params(memoryKib: 32, iterations: 2, parallelism: 1);
      final c = VaultCrypto.forTests(argon2: params);
      final v = await c.createVerifier(
        vmk: vmk,
        realCode: '123456',
        decoyCode: '654321',
      );
      final payload = await c.openVerifier(v, vmk);
      expect(payload.params, params);
      // The stored hash is exactly Argon2id with those parameters.
      final expected =
          await (await DartArgon2id(
                memory: 32,
                iterations: 2,
                parallelism: 1,
                hashLength: 32,
              ).deriveKey(
                secretKey: SecretKey(utf8.encode('123456')),
                nonce: payload.realSalt,
              ))
              .extractBytes();
      expect(payload.realHash, expected);
      // Checking uses the stored cost even if the app's default changes.
      final later = VaultCrypto.forTests(
        argon2: const Argon2Params(
          memoryKib: 64,
          iterations: 1,
          parallelism: 1,
        ),
      );
      expect(await later.checkCode(payload, '123456'), CodeMatch.real);
    });

    test('the phone default is 19 MiB, 2 passes, 1 lane', () {
      expect(Argon2Params.phone.memoryKib, 19456);
      expect(Argon2Params.phone.iterations, 2);
      expect(Argon2Params.phone.parallelism, 1);
    });
  });

  test('slow steps can run on another isolate', () async {
    final c = VaultCrypto(
      worker: isolateWorker,
      argon2: const Argon2Params(memoryKib: 64, iterations: 1, parallelism: 1),
      offloadAbove: 10,
    );
    final vmk = c.randomBytes(32);
    final v = await c.createVerifier(
      vmk: vmk,
      realCode: '123456',
      decoyCode: '654321',
    );
    final payload = await c.openVerifier(v, vmk);
    expect(await c.checkCode(payload, '654321'), CodeMatch.decoy);
    final next = await c.replaceCode(payload, decoyCode: '111111');
    expect(await c.checkCode(next, '111111'), CodeMatch.decoy);
    final sealed = await c.encryptBlob(vmk, 'i', 'photo', Uint8List(64));
    expect(await c.decryptBlob(vmk, 'i', 'photo', sealed), Uint8List(64));
  });

  test('constant-time comparison and code format', () {
    expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
    expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
    expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
    expect(isValidVaultCode('012345'), isTrue);
    expect(isValidVaultCode('12345'), isFalse);
    expect(isValidVaultCode('12345a'), isFalse);
  });
}
