import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/vault/data/vault_crypto.dart';
import 'package:couple_app/features/vault/models/vault_event.dart';
import 'package:couple_app/features/vault/models/vault_item.dart';
import 'package:couple_app/features/vault/providers/vault_providers.dart';
import 'package:couple_app/features/vault/vault_session.dart';

import 'vault_fakes.dart';

/// The vault session: unlocking, decoy routing, cooldowns, auto-lock,
/// approval and codes, against the real service and crypto (fast params).
void main() {
  // Decrypted images are evicted from Flutter's image cache on lock.
  TestWidgetsFlutterBinding.ensureInitialized();

  late VaultTestRig rig;
  late VaultTestPhone ashaPhone;
  late VaultTestPhone raviPhone;

  setUp(() {
    rig = VaultTestRig();
    ashaPhone = VaultTestPhone(uid: asha, name: 'Pixel 8', seed: 1);
    raviPhone = VaultTestPhone(uid: ravi, name: 'Galaxy S23', seed: 2);
  });

  /// A container for [phone], with the session loaded and kept alive.
  Future<(ProviderContainer, VaultSession)> open(VaultTestPhone phone) async {
    final me = vaultUser(phone.uid);
    final partner = vaultUser(phone.uid == asha ? ravi : asha);
    final c = ProviderContainer.test(
      overrides: [
        ...vaultPeopleOverrides(me: me, partner: partner),
        ...rig.overrides(phone),
      ],
    );
    keepAlive(c, [
      vaultSessionProvider,
      vaultItemsProvider,
      vaultAccessProvider,
      vaultPendingDevicesProvider,
    ]);
    await settleAsync();
    expect(c.read(vaultSessionProvider).ready, isTrue);
    return (c, c.read(vaultSessionProvider.notifier));
  }

  Future<List<Map<String, dynamic>>> events() async =>
      (await rig.service.eventsRef(vaultCouple).get()).docs
          .map((d) => d.data())
          .toList();

  group('setting up', () {
    test('creates the vault, approves this phone and opens it', () async {
      final (c, session) = await open(ashaPhone);
      expect(c.read(vaultAccessProvider), VaultAccess.notSetUp);
      await session.setUp(realCode: realCode, decoyCode: decoyCode);
      await settleAsync();
      expect(c.read(vaultAccessProvider), VaultAccess.unlocked);
      final meta = (await rig.service.getMeta(vaultCouple))!;
      final id = c.read(vaultSessionProvider).identity!.deviceId;
      expect(meta.devices[id]!.approved, isTrue);
      expect(meta.devices[id]!.name, 'Pixel 8');
      expect(meta.keys.containsKey(id), isTrue);
      expect(c.read(vaultSessionProvider).shelf, anyOf('a', 'b'));
      // The device key never reaches Firestore: only the public key.
      final stored = ashaPhone.keystore.identities[asha]!;
      expect(meta.devices[id]!.publicKey, stored.publicKeyB64);
    });

    test('the same codes are refused', () async {
      final (_, session) = await open(ashaPhone);
      expect(
        () => session.setUp(realCode: realCode, decoyCode: realCode),
        throwsArgumentError,
      );
    });
  });

  group('decoy routing', () {
    test(
      'the real code opens the real shelf, the decoy code the decoy',
      () async {
        final seeded = await rig.seedVault(ashaPhone, realShelf: 'b');
        await rig.seedMessage(
          crypto: ashaPhone.crypto,
          shelfKey: seeded.keys.vmk,
          shelf: 'b',
          senderId: asha,
          text: 'the real thing',
        );
        await rig.seedMessage(
          crypto: ashaPhone.crypto,
          shelfKey: seeded.keys.dk,
          shelf: 'a',
          senderId: asha,
          text: 'grocery list',
        );
        final (c, session) = await open(ashaPhone);
        expect(c.read(vaultAccessProvider), VaultAccess.locked);

        expect(await session.enterCode(realCode), VaultUnlockResult.unlocked);
        await settleAsync();
        expect(c.read(vaultSessionProvider).shelf, 'b');
        var items = c.read(vaultItemsProvider);
        expect(items, hasLength(1));
        expect(await session.messageText(items.single), 'the real thing');
        expect(session.canApprove, isTrue);

        session.lock();
        expect(c.read(vaultItemsProvider), isEmpty);
        expect(await session.enterCode(decoyCode), VaultUnlockResult.unlocked);
        await settleAsync();
        expect(c.read(vaultSessionProvider).shelf, 'a');
        items = c.read(vaultItemsProvider);
        expect(items, hasLength(1));
        expect(await session.messageText(items.single), 'grocery list');
        // A decoy session can never hand out the real key.
        expect(session.canApprove, isFalse);
      },
    );

    test(
      'items sent in the decoy go to the decoy shelf, under the DK',
      () async {
        final seeded = await rig.seedVault(ashaPhone, realShelf: 'a');
        final (_, session) = await open(ashaPhone);
        await session.enterCode(decoyCode);
        await session.sendMessage('nothing to see', VaultPolicy.keep);
        final item = (await rig.service.getItems(vaultCouple)).single;
        expect(item.shelf, 'b');
        expect(
          await ashaPhone.crypto.decryptContent(
            seeded.keys.dk,
            item.id,
            item.ct,
          ),
          {'type': 'message', 'text': 'nothing to see'},
        );
        expect(
          () => ashaPhone.crypto.decryptContent(
            seeded.keys.vmk,
            item.id,
            item.ct,
          ),
          throwsA(isA<VaultCryptoException>()),
        );
      },
    );

    test(
      'changing the code from the decoy changes only the decoy code',
      () async {
        await rig.seedVault(ashaPhone);
        final (_, session) = await open(ashaPhone);
        await session.enterCode(decoyCode);
        expect(await session.changeCode('111222'), VaultCodeChange.changed);
        // Choosing the real code is refused without saying why.
        expect(await session.changeCode(realCode), VaultCodeChange.rejected);
        session.lock();
        expect(await session.enterCode(decoyCode), VaultUnlockResult.wrong);
        expect(await session.enterCode('111222'), VaultUnlockResult.unlocked);
        session.lock();
        expect(await session.enterCode(realCode), VaultUnlockResult.unlocked);
      },
    );

    test('deleting from the decoy wipes only the decoy shelf', () async {
      final seeded = await rig.seedVault(ashaPhone, realShelf: 'a');
      await rig.seedMessage(
        crypto: ashaPhone.crypto,
        shelfKey: seeded.keys.vmk,
        shelf: 'a',
        senderId: asha,
        text: 'keep me',
      );
      final (_, session) = await open(ashaPhone);
      await session.enterCode(decoyCode);
      await session.sendMessage('decoy', VaultPolicy.keep);
      await session.wipe();
      final items = await rig.service.getItems(vaultCouple);
      expect(items.single.shelf, 'a');
      expect(await rig.service.getMeta(vaultCouple), isNotNull);
      expect(session.isUnlocked, isFalse);
    });
  });

  group('wrong codes', () {
    test('cooldowns escalate: 30 s, 1, 5 and 15 minutes', () async {
      await rig.seedVault(ashaPhone);
      final (c, session) = await open(ashaPhone);
      VaultSessionState state() => c.read(vaultSessionProvider);

      for (var i = 1; i <= 4; i++) {
        expect(await session.enterCode('000000'), VaultUnlockResult.wrong);
      }
      expect(state().cooldownUntil, isNull);
      expect(state().failedAttempts, 4);
      expect(state().wrongCount, 4);

      final expected = [
        const Duration(seconds: 30),
        const Duration(minutes: 1),
        const Duration(minutes: 5),
        const Duration(minutes: 15),
        const Duration(minutes: 15),
      ];
      for (final wait in expected) {
        expect(
          await session.enterCode('000000'),
          VaultUnlockResult.coolingDown,
        );
        expect(state().cooldownUntil, rig.clock.now.add(wait));
        // While cooling down nothing is checked, not even the right code.
        expect(
          await session.enterCode(realCode),
          VaultUnlockResult.coolingDown,
        );
        expect(state().unlocked, isFalse);
        rig.clock.advance(wait + const Duration(seconds: 1));
      }
      expect(state().failedAttempts, 9);

      // Kept on the phone, so restarting the app doesn't reset it.
      final stored = ashaPhone.keystore.states[asha]!;
      expect(stored.failedAttempts, 9);
      expect(stored.cooldownUntil, isNotNull);

      // The partner hears about it.
      final types = (await events()).map((e) => e['type']).toList();
      expect(types.where((t) => t == 'wrongCode'), hasLength(1));
      expect(types.where((t) => t == 'cooldown'), hasLength(5));
      expect((await events()).first['deviceName'], 'Pixel 8');

      // The right code after the cooldown opens it and resets everything.
      expect(await session.enterCode(realCode), VaultUnlockResult.unlocked);
      expect(state().failedAttempts, 0);
      expect(state().cooldownUntil, isNull);
      expect(ashaPhone.keystore.states[asha]!.failedAttempts, 0);
    });

    test('a cooldown survives a new session on the same phone', () async {
      await rig.seedVault(ashaPhone);
      final (c, session) = await open(ashaPhone);
      for (var i = 0; i < 5; i++) {
        await session.enterCode('000000');
      }
      c.dispose();
      final (c2, again) = await open(ashaPhone);
      expect(c2.read(vaultSessionProvider).failedAttempts, 5);
      expect(await again.enterCode(realCode), VaultUnlockResult.coolingDown);
    });
  });

  group('auto-lock', () {
    test('going to the background locks and forgets everything', () async {
      final seeded = await rig.seedVault(ashaPhone);
      await rig.seedMessage(
        crypto: ashaPhone.crypto,
        shelfKey: seeded.keys.vmk,
        shelf: 'a',
        senderId: ravi,
        text: 'hello you',
      );
      final (c, session) = await open(ashaPhone);
      await session.enterCode(realCode);
      await settleAsync();
      final item = c.read(vaultItemsProvider).single;
      await session.messageText(item);
      expect(session.cache.isEmpty, isFalse);

      // Pulling down the shade (inactive) doesn't lock.
      session.handleLifecycle(AppLifecycleState.inactive);
      expect(session.isUnlocked, isTrue);

      session.handleLifecycle(AppLifecycleState.hidden);
      expect(session.isUnlocked, isFalse);
      expect(c.read(vaultSessionProvider).shelf, isNull);
      expect(c.read(vaultSessionProvider).lockCount, 1);
      expect(session.cache.isEmpty, isTrue);
      expect(c.read(vaultItemsProvider), isEmpty);
      expect(() => session.messageText(item), throwsStateError);
    });

    test('a picker or prompt opened by the vault does not lock it', () async {
      await rig.seedVault(ashaPhone);
      final (_, session) = await open(ashaPhone);
      await session.enterCode(realCode);
      final picker = Completer<void>();
      final done = session.suspendWhile(picker.future);
      session.handleLifecycle(AppLifecycleState.paused);
      expect(session.isUnlocked, isTrue);
      picker.complete();
      await done;
      // Coming back within the grace period is still excused...
      session.handleLifecycle(AppLifecycleState.paused);
      expect(session.isUnlocked, isTrue);
      // ...but a later trip to the background locks.
      rig.clock.advance(const Duration(seconds: 5));
      session.handleLifecycle(AppLifecycleState.paused);
      expect(session.isUnlocked, isFalse);
    });
  });

  group('two phones', () {
    test(
      'a new phone waits, gets approved, then opens with the code',
      () async {
        final (ac, ashaSession) = await open(ashaPhone);
        await ashaSession.setUp(realCode: realCode, decoyCode: decoyCode);

        final (rc, raviSession) = await open(raviPhone);
        await settleAsync();
        expect(rc.read(vaultAccessProvider), VaultAccess.unregistered);
        await raviSession.register();
        await settleAsync();
        expect(rc.read(vaultAccessProvider), VaultAccess.pending);
        expect(
          await raviSession.enterCode(realCode),
          VaultUnlockResult.notApproved,
        );

        // Asha's open vault shows the request, with the same safety code.
        final pending = ac.read(vaultPendingDevicesProvider);
        expect(pending.single.name, 'Galaxy S23');
        final raviId = rc.read(vaultSessionProvider).identity!;
        expect(
          pending.single.fingerprint,
          deviceFingerprint(raviId.publicKeyB64),
        );
        await ashaSession.approve(pending.single);
        await settleAsync();
        expect(ac.read(vaultPendingDevicesProvider), isEmpty);
        expect(rc.read(vaultAccessProvider), VaultAccess.locked);

        expect(
          await raviSession.enterCode(realCode),
          VaultUnlockResult.unlocked,
        );
        expect(
          rc.read(vaultSessionProvider).shelf,
          ac.read(vaultSessionProvider).shelf,
        );

        // Messages flow both ways.
        await ashaSession.sendMessage('hi Ravi', VaultPolicy.keep);
        await settleAsync();
        final item = rc.read(vaultItemsProvider).single;
        expect(await raviSession.messageText(item), 'hi Ravi');

        final types = (await events()).map((e) => e['type']).toSet();
        expect(types, containsAll(['deviceAdded', 'deviceApproved']));
      },
    );

    test('the partner resets a forgotten code', () async {
      final seeded = await rig.seedVault(ashaPhone);
      await rig.addPhone(raviPhone, approvedWith: seeded.keys);
      final (_, raviSession) = await open(raviPhone);
      expect(await raviSession.enterCode(realCode), VaultUnlockResult.unlocked);
      // The decoy code can't become the new code.
      expect(await raviSession.changeCode(decoyCode), VaultCodeChange.rejected);
      expect(await raviSession.changeCode('777888'), VaultCodeChange.changed);

      final (_, ashaSession) = await open(ashaPhone);
      expect(await ashaSession.enterCode(realCode), VaultUnlockResult.wrong);
      expect(await ashaSession.enterCode('777888'), VaultUnlockResult.unlocked);
      ashaSession.lock();
      expect(
        await ashaSession.enterCode(decoyCode),
        VaultUnlockResult.unlocked,
      );
      expect((await events()).map((e) => e['type']), contains('codeChanged'));
    });

    test('a decoy code change keeps the other code', () async {
      final seeded = await rig.seedVault(ashaPhone);
      await rig.addPhone(raviPhone, approvedWith: seeded.keys);
      final (_, raviSession) = await open(raviPhone);
      await raviSession.enterCode(realCode);
      expect(
        await raviSession.changeDecoyCode(realCode),
        VaultCodeChange.rejected,
      );
      expect(
        await raviSession.changeDecoyCode('121212'),
        VaultCodeChange.changed,
      );
      raviSession.lock();
      expect(await raviSession.enterCode('121212'), VaultUnlockResult.unlocked);
      raviSession.lock();
      expect(await raviSession.enterCode(realCode), VaultUnlockResult.unlocked);
    });

    test('view once: the recipient\'s view deletes it', () async {
      final seeded = await rig.seedVault(ashaPhone);
      await rig.addPhone(raviPhone, approvedWith: seeded.keys);
      final photoId = await rig.seedPhoto(
        crypto: ashaPhone.crypto,
        shelfKey: seeded.keys.vmk,
        shelf: 'a',
        senderId: asha,
        policy: VaultPolicy.once,
      );
      final (rc, raviSession) = await open(raviPhone);
      await raviSession.enterCode(realCode);
      await settleAsync();
      final item = rc.read(vaultItemsProvider).single;
      expect(item.id, photoId);
      expect(raviSession.isViewOnceForMe(item), isTrue);

      await raviSession.markViewed(item);
      final image = await raviSession.photo(item);
      expect(image.bytes, gradientJpeg());
      await raviSession.finishViewOnce(item);
      expect(await rig.service.getItems(vaultCouple), isEmpty);
      expect(rig.blobs.files, isEmpty);
    });

    test('opening the vault cleans up expired items', () async {
      final seeded = await rig.seedVault(ashaPhone);
      await rig.seedMessage(
        crypto: ashaPhone.crypto,
        shelfKey: seeded.keys.vmk,
        shelf: 'a',
        senderId: ravi,
        text: 'for a day',
        policy: VaultPolicy.day,
        at: rig.clock.now.subtract(const Duration(hours: 25)),
      );
      final (c, session) = await open(ashaPhone);
      expect(await session.enterCode(realCode), VaultUnlockResult.unlocked);
      // Hidden straight away, deleted soon after.
      expect(c.read(vaultItemsProvider), isEmpty);
      await settleAsync();
      expect(await rig.service.getItems(vaultCouple), isEmpty);
    });
  });

  test('fingerprint unlock opens the real shelf when on', () async {
    await rig.seedVault(ashaPhone, realShelf: 'b');
    final (c, session) = await open(ashaPhone);
    expect(await session.unlockWithBiometrics(), VaultUnlockResult.failed);
    expect(await session.setBiometric(true), isTrue);
    expect(ashaPhone.keystore.states[asha]!.biometric, isTrue);
    rig.biometrics.result = false;
    expect(await session.unlockWithBiometrics(), VaultUnlockResult.cancelled);
    rig.biometrics.result = true;
    expect(await session.unlockWithBiometrics(), VaultUnlockResult.unlocked);
    expect(c.read(vaultSessionProvider).shelf, 'b');
  });

  test('alerts from the partner are listed; own alerts are not', () async {
    final (c, _) = await open(ashaPhone);
    keepAlive(c, [vaultAlertsProvider]);
    await rig.service.addEvent(
      cid: vaultCouple,
      type: VaultEventType.cooldown,
      uid: ravi,
      deviceName: 'Galaxy S23',
    );
    await rig.service.addEvent(
      cid: vaultCouple,
      type: VaultEventType.codeChanged,
      uid: asha,
      deviceName: 'Pixel 8',
    );
    await settleAsync();
    final alerts = c.read(vaultAlertsProvider);
    expect(alerts.single.type, VaultEventType.cooldown);
  });
}
