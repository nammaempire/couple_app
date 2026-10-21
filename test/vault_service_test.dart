import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/vault/data/vault_crypto.dart';
import 'package:couple_app/features/vault/data/vault_service.dart';
import 'package:couple_app/features/vault/models/vault_event.dart';
import 'package:couple_app/features/vault/models/vault_item.dart';
import 'package:couple_app/features/vault/models/vault_meta.dart';

/// The real VaultService against an in-memory Firestore and file store.
void main() {
  const cid = 'c1';
  const asha = 'asha';
  const ravi = 'ravi';
  late FakeFirebaseFirestore db;
  late MemoryVaultBlobStore blobs;
  late VaultService service;

  const keys = WrappedKeys(vmk: 'wrapped-vmk', dk: 'wrapped-dk');

  VaultDevice device(
    String id, {
    String uid = asha,
    bool approved = false,
    String name = 'Pixel 8',
  }) => VaultDevice(
    id: id,
    uid: uid,
    publicKey: 'pk-$id',
    name: name,
    approved: approved,
  );

  Future<Map<String, dynamic>> metaData() async =>
      (await service.metaRef(cid).get()).data()!;

  Future<List<Map<String, dynamic>>> events() async =>
      (await service.eventsRef(cid).get()).docs.map((d) => d.data()).toList();

  Future<void> createVault() => service.createVault(
    cid: cid,
    uid: asha,
    device: device('d1', approved: true),
    keys: keys,
    verifier: 'sealed-verifier',
  );

  setUp(() {
    db = FakeFirebaseFirestore();
    blobs = MemoryVaultBlobStore();
    service = VaultService(firestore: db, blobs: blobs);
  });

  group('setup and phones', () {
    test('creates meta with the creator\'s phone approved', () async {
      expect(await service.getMeta(cid), isNull);
      await createVault();
      final data = await metaData();
      expect(data['version'], 1);
      expect(data['createdBy'], asha);
      expect(data['createdAt'], isA<Timestamp>());
      expect(data['verifier'], 'sealed-verifier');
      expect(data['updatedBy'], asha);
      expect(data['devices'], {
        'd1': {
          'uid': asha,
          'publicKey': 'pk-d1',
          'name': 'Pixel 8',
          'approved': true,
          'addedAt': isA<Timestamp>(),
        },
      });
      expect(data['keys'], {
        'd1': {'vmk': 'wrapped-vmk', 'dk': 'wrapped-dk'},
      });
      final meta = (await service.getMeta(cid))!;
      expect(meta.devices['d1']!.approved, isTrue);
      expect(meta.keys['d1']!.vmk, 'wrapped-vmk');
      expect(meta.pending, isEmpty);
    });

    test('a second setup is refused', () async {
      await createVault();
      expect(createVault, throwsA(isA<VaultExistsException>()));
    });

    test('registering adds an unapproved phone and an alert', () async {
      await createVault();
      await service.registerDevice(
        cid: cid,
        device: device('d2', uid: ravi, name: 'Galaxy S23'),
      );
      final meta = (await service.getMeta(cid))!;
      expect(meta.devices['d2']!.approved, isFalse);
      expect(meta.devices['d2']!.uid, ravi);
      expect(meta.keys.containsKey('d2'), isFalse);
      expect(meta.pending.map((d) => d.id), ['d2']);
      expect((await metaData())['updatedBy'], ravi);
      expect(await events(), [
        {
          'type': 'deviceAdded',
          'uid': ravi,
          'deviceName': 'Galaxy S23',
          'at': isA<Timestamp>(),
        },
      ]);

      // Registering again is a no-op.
      await service.registerDevice(
        cid: cid,
        device: device('d2', uid: ravi),
      );
      expect(await events(), hasLength(1));
    });

    test('at most eight phones', () async {
      await createVault();
      for (var i = 2; i <= VaultMeta.maxDevices; i++) {
        await service.registerDevice(cid: cid, device: device('d$i'));
      }
      expect(
        () => service.registerDevice(cid: cid, device: device('d9')),
        throwsA(isA<VaultDeviceLimitException>()),
      );
    });

    test('approving writes the sealed keys and the flag', () async {
      await createVault();
      await service.registerDevice(
        cid: cid,
        device: device('d2', uid: ravi),
      );
      await service.approveDevice(
        cid: cid,
        uid: asha,
        deviceId: 'd2',
        keys: const WrappedKeys(vmk: 'v2', dk: 'k2'),
        approverDeviceName: 'Pixel 8',
      );
      final meta = (await service.getMeta(cid))!;
      expect(meta.devices['d2']!.approved, isTrue);
      expect(meta.keys['d2']!.dk, 'k2');
      expect(meta.pending, isEmpty);
      expect((await events()).map((e) => e['type']), [
        'deviceAdded',
        'deviceApproved',
      ]);
    });

    test('a new verifier is written with an alert', () async {
      await createVault();
      await service.setVerifier(
        cid: cid,
        uid: ravi,
        verifier: 'v2',
        deviceName: 'Galaxy S23',
      );
      final data = await metaData();
      expect(data['verifier'], 'v2');
      expect(data['updatedBy'], ravi);
      expect((await events()).single['type'], 'codeChanged');
    });

    test('device names are trimmed to 60 characters', () {
      expect(VaultService.clampName('x' * 80), hasLength(60));
      expect(VaultService.clampName('  '), 'Phone');
    });
  });

  group('items', () {
    test('a message is stored with the contract\'s fields', () async {
      final id = service.newItemId(cid);
      final now = DateTime(2026, 10, 20, 9);
      await service.addMessage(
        cid: cid,
        itemId: id,
        senderId: asha,
        shelf: 'b',
        ct: 'ciphertext',
        policy: VaultPolicy.day,
        now: now,
      );
      final data = (await service.itemsRef(cid).doc(id).get()).data()!;
      expect(data, {
        'senderId': asha,
        'kind': 'message',
        'shelf': 'b',
        'ct': 'ciphertext',
        'photoPath': null,
        'thumbPath': null,
        'policy': 'day',
        'expiresAt': Timestamp.fromDate(now.add(const Duration(hours: 24))),
        'viewedBy': <String, dynamic>{},
        'createdAt': isA<Timestamp>(),
      });
      final item = (await service.getItems(cid)).single;
      expect(item.kind, VaultItemKind.message);
      expect(item.policy, VaultPolicy.day);
    });

    test('keep and view-once never expire', () async {
      for (final policy in [VaultPolicy.keep, VaultPolicy.once]) {
        final id = service.newItemId(cid);
        await service.addMessage(
          cid: cid,
          itemId: id,
          senderId: asha,
          shelf: 'a',
          ct: 'x',
          policy: policy,
        );
        final data = (await service.itemsRef(cid).doc(id).get()).data()!;
        expect(data['expiresAt'], isNull);
        expect(data['policy'], policy.value);
      }
    });

    test('content over 20000 characters is refused', () async {
      expect(
        () => service.addMessage(
          cid: cid,
          itemId: 'x',
          senderId: asha,
          shelf: 'a',
          ct: 'x' * 20001,
          policy: VaultPolicy.keep,
        ),
        throwsArgumentError,
      );
    });

    test('a photo uploads both files, then the item', () async {
      final id = service.newItemId(cid);
      final photoPath = service.newFilePath(cid);
      final thumbPath = service.newFilePath(cid);
      expect(photoPath, startsWith('couples/c1/vault/'));
      expect(photoPath, isNot(thumbPath));
      final progress = <double>[];
      await service.addPhoto(
        cid: cid,
        itemId: id,
        senderId: ravi,
        shelf: 'a',
        ct: 'ct',
        policy: VaultPolicy.once,
        photoPath: photoPath,
        photo: Uint8List(300),
        thumbPath: thumbPath,
        thumb: Uint8List(100),
        onProgress: progress.add,
      );
      expect(blobs.files.keys, unorderedEquals([photoPath, thumbPath]));
      expect(progress.last, 1.0);
      expect(progress, orderedEquals([...progress]..sort()));
      final item = (await service.getItems(cid)).single;
      expect(item.kind, VaultItemKind.photo);
      expect(item.photoPath, photoPath);
      expect(item.thumbPath, thumbPath);
      expect(await service.download(photoPath), Uint8List(300));
    });

    test('viewing once: marked, then deleted with its files', () async {
      final id = service.newItemId(cid);
      final photoPath = service.newFilePath(cid);
      final thumbPath = service.newFilePath(cid);
      await service.addPhoto(
        cid: cid,
        itemId: id,
        senderId: asha,
        shelf: 'a',
        ct: 'ct',
        policy: VaultPolicy.once,
        photoPath: photoPath,
        photo: Uint8List(10),
        thumbPath: thumbPath,
        thumb: Uint8List(5),
      );
      await service.markViewed(cid: cid, itemId: id, uid: ravi);
      final item = (await service.getItems(cid)).single;
      expect(item.viewedByUid(ravi), isTrue);
      expect(item.viewedByUid(asha), isFalse);

      await service.deleteItem(cid, item);
      expect(await service.getItems(cid), isEmpty);
      expect(blobs.files, isEmpty);
    });

    test('clean-up deletes expired and already-seen view-once items', () async {
      final now = DateTime(2026, 10, 20, 12);
      Future<String> add(VaultPolicy policy, DateTime at, String sender) async {
        final id = service.newItemId(cid);
        await service.addMessage(
          cid: cid,
          itemId: id,
          senderId: sender,
          shelf: 'a',
          ct: 'x',
          policy: policy,
          now: at,
        );
        return id;
      }

      final expired = await add(
        VaultPolicy.day,
        now.subtract(const Duration(hours: 25)),
        asha,
      );
      final fresh = await add(
        VaultPolicy.day,
        now.subtract(const Duration(hours: 1)),
        asha,
      );
      final kept = await add(VaultPolicy.keep, now, asha);
      final seenByRavi = await add(VaultPolicy.once, now, asha);
      final unseen = await add(VaultPolicy.once, now, asha);
      await service.markViewed(cid: cid, itemId: seenByRavi, uid: ravi);

      final deleted = await service.cleanUp(cid: cid, uid: ravi, now: now);
      expect(deleted, 2);
      final left = (await service.getItems(cid)).map((i) => i.id);
      expect(left, unorderedEquals([fresh, kept, unseen]));
      expect(left, isNot(contains(expired)));

      // The sender's phone never deletes its own unseen view-once items.
      expect(await service.cleanUp(cid: cid, uid: asha, now: now), 0);
    });

    test('expired items on the other shelf are cleaned up too', () async {
      final id = service.newItemId(cid);
      await service.addMessage(
        cid: cid,
        itemId: id,
        senderId: asha,
        shelf: 'b',
        ct: 'x',
        policy: VaultPolicy.day,
        now: DateTime(2026, 1, 1),
      );
      expect(
        await service.cleanUp(cid: cid, uid: asha, now: DateTime(2026, 1, 3)),
        1,
      );
    });
  });

  group('alerts and wiping', () {
    test('alerts are listed newest first and can be dismissed', () async {
      await service.addEvent(
        cid: cid,
        type: VaultEventType.wrongCode,
        uid: ravi,
        deviceName: 'Galaxy S23',
      );
      final list = await service.watchEvents(cid).first;
      expect(list.single.type, VaultEventType.wrongCode);
      expect(list.single.describe('Ravi'), contains('Galaxy S23'));
      await service.dismissEvent(cid, list.single.id);
      expect(await service.watchEvents(cid).first, isEmpty);
    });

    test('wipe deletes everything and leaves one alert', () async {
      await createVault();
      for (final shelf in ['a', 'b']) {
        await service.addPhoto(
          cid: cid,
          itemId: service.newItemId(cid),
          senderId: asha,
          shelf: shelf,
          ct: 'ct',
          policy: VaultPolicy.keep,
          photoPath: service.newFilePath(cid),
          photo: Uint8List(4),
          thumbPath: service.newFilePath(cid),
          thumb: Uint8List(2),
        );
      }
      await service.addEvent(
        cid: cid,
        type: VaultEventType.codeChanged,
        uid: ravi,
        deviceName: 'S23',
      );
      await service.wipe(cid: cid, uid: asha, deviceName: 'Pixel 8');
      expect(await service.getMeta(cid), isNull);
      expect(await service.getItems(cid), isEmpty);
      expect(blobs.files, isEmpty);
      final left = await events();
      expect(left.single['type'], 'wiped');
      expect(left.single['uid'], asha);
    });

    test('wiping one shelf leaves the other and the meta', () async {
      await createVault();
      for (final shelf in ['a', 'b']) {
        await service.addMessage(
          cid: cid,
          itemId: service.newItemId(cid),
          senderId: asha,
          shelf: shelf,
          ct: 'x',
          policy: VaultPolicy.keep,
        );
      }
      await service.wipeShelf(
        cid: cid,
        shelf: 'b',
        uid: asha,
        deviceName: 'Pixel 8',
      );
      expect((await service.getItems(cid)).single.shelf, 'a');
      expect(await service.getMeta(cid), isNotNull);
      expect((await events()).single['type'], 'wiped');
    });
  });
}
