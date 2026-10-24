import 'package:couple_app/core/backend/backend.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/core/theme/app_theme.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/auth/screens/auth_gate.dart';
import 'package:couple_app/features/calls/data/call_service.dart';
import 'package:couple_app/features/calls/models/call_session.dart';
import 'package:couple_app/features/calls/widgets/incoming_call_listener.dart';
import 'package:couple_app/features/chat/data/chat_service.dart';
import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/providers/chat_providers.dart';
import 'package:couple_app/features/chat/widgets/chat_privacy_scope.dart';
import 'package:couple_app/features/chat/widgets/message_actions_sheet.dart';
import 'package:couple_app/features/couple/data/end_pairing_gateway.dart';
import 'package:couple_app/features/couple/data/separation_service.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/models/separation.dart';
import 'package:couple_app/features/couple/providers/separation_providers.dart';
import 'package:couple_app/features/couple/widgets/separation_banner.dart';
import 'package:couple_app/features/memories/data/memory_service.dart';
import 'package:couple_app/features/memories/models/memory.dart';
import 'package:couple_app/features/memories/providers/memory_providers.dart';
import 'package:couple_app/features/memories/screens/memory_detail_screen.dart';
import 'package:couple_app/features/us/screens/end_pairing_screen.dart';
import 'package:couple_app/features/vault/providers/vault_providers.dart';
import 'package:couple_app/features/vault/screens/vault_screen.dart';
import 'package:couple_app/features/vault/widgets/vault_us_row.dart';

import 'pairing_fakes.dart';
import 'vault_fakes.dart' as vault;

class _FakeUser implements User {
  _FakeUser(this.uid);

  @override
  final String uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<Map<String, dynamic>?> separationOf(PairingRig rig) async =>
    (await rig.couple.get()).data()!['separation'] as Map<String, dynamic>?;

Future<Separation> current(PairingRig rig) async =>
    Couple.fromDoc(await rig.couple.get()).separation!;

void main() {
  late PairingRig rig;
  late DateTime t0;

  setUp(() {
    rig = PairingRig();
    t0 = rig.now;
  });

  group('Separation', () {
    test('countdown text', () {
      expect(Separation.countdown(const Duration(days: 14)), '14 days left');
      expect(
        Separation.countdown(const Duration(days: 13, hours: 1)),
        '14 days left',
      );
      expect(Separation.countdown(const Duration(days: 1)), '1 day left');
      expect(Separation.countdown(const Duration(hours: 5)), '5 hours left');
      expect(
        Separation.countdown(const Duration(minutes: 20)),
        'Less than an hour left',
      );
      expect(Separation.countdown(Duration.zero), 'Ending now');
    });

    test('reads the map, and ignores a malformed one', () {
      final s = Separation.fromMap({
        'requestedBy': pAsha,
        'status': 'declined',
        'effectiveAt': Timestamp.fromDate(t0),
      })!;
      expect(s.status, SeparationStatus.declined);
      expect(s.isDue(t0), isTrue);
      expect(Separation.fromMap({'status': 'requested'}), isNull);
      expect(Separation.fromMap(null), isNull);
    });
  });

  group('SeparationService', () {
    late SeparationService service;

    setUp(() async {
      await rig.seedCouple();
      service = rig.separations;
    });

    test('request writes exactly the contract, ending in 14 days', () async {
      await service.request(coupleId: pCouple, uid: pAsha, current: null);
      final s = (await separationOf(rig))!;
      expect(s.keys.toSet(), {
        'requestedBy',
        'requestedAt',
        'status',
        'agreedAt',
        'declinedAt',
        'effectiveAt',
      });
      expect(s['requestedBy'], pAsha);
      expect(s['requestedAt'], isA<Timestamp>());
      expect(s['status'], 'requested');
      expect(s['agreedAt'], isNull);
      expect(s['declinedAt'], isNull);
      expect(
        (s['effectiveAt'] as Timestamp).toDate(),
        t0.add(const Duration(days: 14)),
      );
    });

    test('cannot ask twice', () async {
      await service.request(coupleId: pCouple, uid: pAsha, current: null);
      expect(
        () async => service.request(
          coupleId: pCouple,
          uid: pRavi,
          current: await current(rig),
        ),
        throwsA(isA<SeparationException>()),
      );
    });

    test('agree a day later: 7 days from now, sooner than 14', () async {
      await service.request(coupleId: pCouple, uid: pAsha, current: null);
      rig.now = t0.add(const Duration(days: 1));
      await service.agree(
        coupleId: pCouple,
        uid: pRavi,
        current: await current(rig),
      );
      final s = await current(rig);
      expect(s.status, SeparationStatus.agreed);
      expect(s.agreedAt, isNotNull);
      expect(s.effectiveAt, t0.add(const Duration(days: 8)));
    });

    test('agree late: keeps the sooner original date untouched', () async {
      await service.request(coupleId: pCouple, uid: pAsha, current: null);
      rig.now = t0.add(const Duration(days: 10));
      await service.agree(
        coupleId: pCouple,
        uid: pRavi,
        current: await current(rig),
      );
      final s = await current(rig);
      expect(s.status, SeparationStatus.agreed);
      expect(s.effectiveAt, t0.add(const Duration(days: 14)));
    });

    test('only the other partner can agree or decline', () async {
      await service.request(coupleId: pCouple, uid: pAsha, current: null);
      final s = await current(rig);
      expect(
        () => service.agree(coupleId: pCouple, uid: pAsha, current: s),
        throwsA(isA<SeparationException>()),
      );
      expect(
        () => service.decline(coupleId: pCouple, uid: pAsha, current: s),
        throwsA(isA<SeparationException>()),
      );
    });

    test('decline keeps the date; agreeing later still works', () async {
      await service.request(coupleId: pCouple, uid: pAsha, current: null);
      await service.decline(
        coupleId: pCouple,
        uid: pRavi,
        current: await current(rig),
      );
      var s = await current(rig);
      expect(s.status, SeparationStatus.declined);
      expect(s.declinedAt, isNotNull);
      expect(s.effectiveAt, t0.add(const Duration(days: 14)));
      expect(
        () => service.decline(coupleId: pCouple, uid: pRavi, current: s),
        throwsA(isA<SeparationException>()),
      );

      rig.now = t0.add(const Duration(days: 2));
      await service.agree(coupleId: pCouple, uid: pRavi, current: s);
      s = await current(rig);
      expect(s.status, SeparationStatus.agreed);
      expect(s.declinedAt, isNotNull);
      expect(s.effectiveAt, t0.add(const Duration(days: 9)));
    });

    test('only the one who asked can cancel', () async {
      await service.request(coupleId: pCouple, uid: pAsha, current: null);
      await expectLater(
        service.cancel(
          coupleId: pCouple,
          uid: pRavi,
          current: await current(rig),
        ),
        throwsA(isA<SeparationException>()),
      );
      expect(await separationOf(rig), isNotNull);

      await service.cancel(
        coupleId: pCouple,
        uid: pAsha,
        current: await current(rig),
      );
      expect((await rig.couple.get()).data()!.containsKey('separation'), false);
    });

    test('mute toggles on the profile', () async {
      await service.setMutePartner(uid: pAsha, muted: true);
      var doc = await rig.db.collection('users').doc(pAsha).get();
      expect(doc.data()!['mutePartner'], isTrue);
      await service.setMutePartner(uid: pAsha, muted: false);
      doc = await rig.db.collection('users').doc(pAsha).get();
      expect(doc.data()!['mutePartner'], isFalse);
    });

    test('clears the "pairing ended" marker', () async {
      await rig.db.collection('users').doc(pAsha).update({
        'pairingEndedAt': Timestamp.fromDate(t0),
        'pairingEndedHow': 'agreed',
      });
      await service.clearPairingEnded(pAsha);
      final data = (await rig.db.collection('users').doc(pAsha).get()).data()!;
      expect(data.containsKey('pairingEndedAt'), isFalse);
      expect(data.containsKey('pairingEndedHow'), isFalse);
    });
  });

  group('FunctionsEndPairingGateway', () {
    test('maps callable errors', () {
      for (final code in ['not-found', 'UNAVAILABLE', 'internal']) {
        expect(
          FunctionsEndPairingGateway.failureForCode(code),
          EndPairingFailure.unavailable,
        );
      }
      expect(
        FunctionsEndPairingGateway.failureForCode('permission-denied'),
        EndPairingFailure.denied,
      );
      expect(
        FunctionsEndPairingGateway.failureForCode('failed-precondition'),
        EndPairingFailure.notReady,
      );
      expect(
        FunctionsEndPairingGateway.failureForCode('invalid-argument'),
        EndPairingFailure.other,
      );
    });

    test('reads {status, how} and the "not yet" date', () {
      final done = FunctionsEndPairingGateway.parseResult({
        'status': 'alreadyEnded',
        'how': 'agreed',
      });
      expect(done.isDone, isTrue);
      expect(done.how, 'agreed');
      expect(
        FunctionsEndPairingGateway.parseResult({
          'status': 'inProgress',
          'how': null,
        }).status,
        EndPairingStatus.inProgress,
      );
      expect(
        FunctionsEndPairingGateway.notBeforeFrom({
          'effectiveAt': '2026-11-04T10:00:00.000Z',
        }),
        DateTime.utc(2026, 11, 4, 10).toLocal(),
      );
    });
  });

  group('banner', () {
    Future<void> pump(
      WidgetTester tester,
      String uid,
      Widget child, {
      List<dynamic> extra = const [],
      bool settle = true,
    }) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [...rig.overrides(uid), ...extra.cast()],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: PairingReady(
                uid: uid,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [child],
                ),
              ),
            ),
          ),
        ),
      );
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        // A spinner never settles.
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }
    }

    testWidgets('requester: ends on, cancel and mute', (tester) async {
      await rig.seedCouple(separation: rig.separationMap());
      await pump(tester, pAsha, const SeparationBanner());

      expect(find.text('Your pairing ends on 4\u00A0Nov'), findsOneWidget);
      expect(
        find.text('Everything you shared will be deleted.'),
        findsOneWidget,
      );
      expect(find.text('14 days left'), findsOneWidget);
      expect(find.text('Agree'), findsNothing);

      await tester.tap(find.text('Mute Ravi'));
      await tester.pumpAndSettle();
      expect(find.text('Unmute Ravi'), findsOneWidget);
      final asha = await rig.db.collection('users').doc(pAsha).get();
      expect(asha.data()!['mutePartner'], isTrue);

      await tester.tap(find.text('Cancel (we\'re staying together)'));
      await tester.pumpAndSettle();
      expect(await separationOf(rig), isNull);
      expect(find.byKey(const Key('separation-banner')), findsNothing);
    });

    testWidgets('partner: agree or decline; message after declining', (
      tester,
    ) async {
      await rig.seedCouple(separation: rig.separationMap());
      var opened = 0;
      await pump(tester, pRavi, SeparationBanner(onOpenChat: () => opened++));

      expect(find.text('Asha wants to end your pairing'), findsOneWidget);
      expect(
        find.text(
          'Your pairing ends on 4\u00A0Nov. Everything you shared will be deleted.',
        ),
        findsOneWidget,
      );
      expect(find.text('Cancel (we\'re staying together)'), findsNothing);

      await tester.tap(find.text('I don\'t want this'));
      await tester.pumpAndSettle();
      expect((await current(rig)).status, SeparationStatus.declined);
      expect(find.text('You said you don\'t want this'), findsOneWidget);
      expect(
        find.text(
          'Asha can still end it on 4\u00A0Nov. You can message them or ask to '
          'talk.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Message Asha'));
      expect(opened, 1);

      // Still free to agree later: 7 days from now.
      rig.now = t0.add(const Duration(days: 1));
      await tester.tap(find.text('Agree'));
      await tester.pumpAndSettle();
      expect(find.text('Agree to end your pairing?'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Agree'),
        ),
      );
      await tester.pumpAndSettle();
      final s = await current(rig);
      expect(s.status, SeparationStatus.agreed);
      expect(s.effectiveAt, t0.add(const Duration(days: 8)));
      expect(find.text('You both agreed to end your pairing'), findsOneWidget);
    });

    testWidgets('the countdown follows the clock', (tester) async {
      await rig.seedCouple(separation: rig.separationMap());
      rig.now = t0.add(const Duration(days: 13));
      await pump(tester, pRavi, const SeparationBanner());
      expect(find.text('1 day left'), findsOneWidget);
      rig.now = t0.add(const Duration(days: 13, hours: 19));
      await pump(tester, pRavi, const SeparationBanner());
      expect(find.text('5 hours left'), findsOneWidget);
    });

    testWidgets('the chat strip opens the full card', (tester) async {
      await rig.seedCouple(separation: rig.separationMap());
      await pump(tester, pRavi, const SeparationBanner(compact: true));
      expect(
        find.text('Asha wants to end your pairing · Tap to answer'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('separation-strip')));
      await tester.pumpAndSettle();
      expect(find.text('Asha wants to end your pairing'), findsOneWidget);
      expect(find.text('Agree'), findsOneWidget);
    });

    testWidgets('after the date: asks the server, and waits gracefully', (
      tester,
    ) async {
      await rig.seedCouple(separation: rig.separationMap());
      rig.now = t0.add(const Duration(days: 14, minutes: 1));
      rig.endGateway.error = EndPairingException(
        EndPairingFailure.unavailable,
        'NOT_FOUND',
      );
      await pump(
        tester,
        pAsha,
        const _Finalizes(child: SeparationBanner()),
        settle: false,
        extra: [
          separationRetryDelayProvider.overrideWithValue(
            const Duration(minutes: 2),
          ),
        ],
      );
      expect(rig.endGateway.finalized, [pCouple]);
      expect(find.text('Waiting for the server to finish'), findsOneWidget);
      expect(find.text('Cancel (we\'re staying together)'), findsNothing);

      // It tries again later; this time the server is there.
      rig.endGateway.error = null;
      await tester.pump(const Duration(minutes: 2));
      await tester.pump();
      expect(rig.endGateway.finalized, [pCouple, pCouple]);
      expect(find.text('Ending your pairing…'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('before the date nothing is asked', (tester) async {
      await rig.seedCouple(separation: rig.separationMap());
      await pump(tester, pAsha, const _Finalizes(child: SeparationBanner()));
      expect(rig.endGateway.finalized, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the server\'s "ending" marker shows progress', (tester) async {
      await rig.seedCouple(separation: rig.separationMap());
      await rig.couple.update({
        'ending': {'how': 'oneSided', 'startedAt': Timestamp.fromDate(t0)},
      });
      await pump(tester, pRavi, const SeparationBanner(), settle: false);
      expect(find.text('Ending your pairing…'), findsOneWidget);
      expect(find.text('Agree'), findsNothing);
    });
  });

  group('closed while separating', () {
    List<dynamic> vaultOverrides() {
      final vrig = vault.VaultTestRig(db: rig.db);
      final phone = vault.VaultTestPhone(uid: pAsha, name: 'Pixel', seed: 1);
      return [
        vaultServiceProvider.overrideWithValue(vrig.service),
        deviceKeystoreProvider.overrideWithValue(phone.keystore),
        vaultCryptoProvider.overrideWithValue(phone.crypto),
        vaultClockProvider.overrideWithValue(vrig.clock.call),
        deviceNameSourceProvider.overrideWithValue(
          vault.FakeDeviceName(phone.name),
        ),
        vaultPhotoSourceProvider.overrideWithValue(vrig.photos),
      ];
    }

    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            ...rig.overrides(pAsha),
            ...vaultOverrides().cast(),
            memoryServiceProvider.overrideWithValue(MemoryService(db: rig.db)),
            chatServiceProvider.overrideWithValue(
              ChatService(db: rig.db, storage: FakeStorageService()),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: PairingReady(uid: pAsha, child: child),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the vault row and screen are closed', (tester) async {
      await rig.seedCouple(separation: rig.separationMap());
      await pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => ListView(
              children: [
                const VaultUsRow(),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).push(VaultScreen.route()),
                  child: const Text('open vault'),
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        find.text('Private is closed while your pairing ends'),
        findsOneWidget,
      );
      await tester.tap(find.text('Private'));
      await tester.pumpAndSettle();
      expect(find.byType(VaultScreen), findsNothing);

      await tester.tap(find.text('open vault'));
      await tester.pumpAndSettle();
      expect(find.text('Private is closed'), findsOneWidget);
    });

    testWidgets('the vault opens normally otherwise', (tester) async {
      await rig.seedCouple();
      await pump(tester, const Scaffold(body: VaultUsRow()));
      expect(find.text('Only for the two of you'), findsOneWidget);
    });

    Future<void> seedMemory() =>
        rig.couple.collection('memories').doc('m1').set({
          'title': 'Goa',
          'date': Timestamp.fromDate(t0),
          'album': 'Trips',
          'createdBy': pAsha,
          'media': <dynamic>[],
        });

    final memory = Memory(
      id: 'm1',
      title: 'Goa',
      date: DateTime(2026, 10, 1),
      album: 'Trips',
      createdBy: pAsha,
    );

    testWidgets('memories: no share or save while separating', (tester) async {
      await rig.seedCouple(separation: rig.separationMap());
      await seedMemory();
      await pump(tester, MemoryDetailScreen(memoryId: 'm1', initial: memory));
      expect(find.byTooltip('Share or save'), findsNothing);
    });

    testWidgets('memories: share is there otherwise', (tester) async {
      await rig.seedCouple();
      await seedMemory();
      await pump(tester, MemoryDetailScreen(memoryId: 'm1', initial: memory));
      expect(find.byTooltip('Share or save'), findsOneWidget);
    });

    testWidgets('chat: no copying out, and screenshots are blocked', (
      tester,
    ) async {
      await rig.seedCouple(separation: rig.separationMap());
      late WidgetRef widgetRef;
      await pump(
        tester,
        Scaffold(
          body: ChatPrivacyScope(
            child: Consumer(
              builder: (context, ref, _) {
                widgetRef = ref;
                return MessageActionsSheet(
                  message: const Message(
                    id: 'x',
                    senderId: pRavi,
                    type: MessageType.text,
                    text: 'hi',
                  ),
                  myUid: pAsha,
                  allowCopy: !ref.watch(separationActiveProvider),
                  onReact: (_) {},
                  onReply: () {},
                  onCopy: () {},
                  onTogglePin: () {},
                  onDelete: () {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('Copy text'), findsNothing);
      expect(find.text('Reply'), findsOneWidget);
      expect(widgetRef.read(blockScreenshotsProvider), isTrue);
      expect(rig.security.secure, isTrue);

      // Called off: copying and screenshots are back to the couple's choice.
      await rig.couple.update({'separation': FieldValue.delete()});
      await tester.pumpAndSettle();
      expect(find.text('Copy text'), findsOneWidget);
      expect(rig.security.secure, isFalse);
    });
  });

  group('end pairing', () {
    Future<void> pumpUs(WidgetTester tester, {String uid = pAsha}) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: rig.overrides(uid),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: PairingReady(
              uid: uid,
              child: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () =>
                        Navigator.of(context).push(EndPairingScreen.route()),
                    child: const Text('end'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('end'));
      await tester.pumpAndSettle();
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('explains, checks it\'s you, then asks', (tester) async {
      await rig.seedCouple();
      await pumpUs(tester);
      expect(find.text('Ending your pairing'), findsOneWidget);
      expect(find.text('Ravi is told, gently'), findsOneWidget);

      await tapKey(tester, 'end-pairing-confirm');
      expect(rig.biometrics.reasons, hasLength(1));
      final s = await current(rig);
      expect(s.requestedBy, pAsha);
      expect(s.effectiveAt, t0.add(const Duration(days: 14)));
      expect(find.text('end'), findsOneWidget);
    });

    testWidgets('a failed lock prompt asks nothing', (tester) async {
      await rig.seedCouple();
      rig.biometrics.result = false;
      await pumpUs(tester);
      await tapKey(tester, 'end-pairing-confirm');
      expect(await separationOf(rig), isNull);
    });

    testWidgets('no screen lock: type END instead', (tester) async {
      await rig.seedCouple();
      rig.biometrics.available = false;
      await pumpUs(tester);
      await tapKey(tester, 'end-pairing-confirm');
      final go = find.widgetWithText(FilledButton, 'Continue');
      expect(tester.widget<FilledButton>(go).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('type-to-confirm')), 'end');
      await tester.pump();
      await tester.tap(go);
      await tester.pumpAndSettle();
      expect(await separationOf(rig), isNotNull);
    });

    Future<void> openLeaveNow(WidgetTester tester) =>
        tapKey(tester, 'leave-now-link');

    Future<void> confirmLeave(WidgetTester tester) async {
      final go = find.byKey(const Key('leave-now-confirm'));
      expect(tester.widget<FilledButton>(go).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('leave-word')), 'LEAVE');
      await tester.pump();
      expect(tester.widget<FilledButton>(go).onPressed, isNull);
      await tester.ensureVisible(find.byKey(const Key('leave-understood')));
      await tester.tap(find.byKey(const Key('leave-understood')));
      await tester.pump();
      expect(tester.widget<FilledButton>(go).onPressed, isNotNull);
      await tester.ensureVisible(go);
      await tester.tap(go);
      await tester.pump();
    }

    testWidgets('leave now: lock, LEAVE, the checkbox, then the server', (
      tester,
    ) async {
      await rig.seedCouple();
      rig.endGateway.onEnd = (cid, how) async {
        // What the server does: unlink both and leave the marker.
        for (final uid in [pAsha, pRavi]) {
          await rig.db.collection('users').doc(uid).update({
            'coupleId': null,
            'pairingEndedAt': Timestamp.fromDate(rig.now),
            'pairingEndedHow': how,
          });
        }
      };
      await pumpUs(tester);
      await openLeaveNow(tester);
      expect(rig.biometrics.reasons.single, contains('leave now'));
      expect(find.text('Leave now'), findsOneWidget);

      await confirmLeave(tester);
      expect(rig.endGateway.leftNow, [pCouple]);
      await tester.pumpAndSettle();
      // Back to the root once unpaired, where the gate shows "ended".
      expect(find.text('Leave now'), findsNothing);
    });

    testWidgets('leave now without the server offers the 14-day route', (
      tester,
    ) async {
      await rig.seedCouple();
      rig.endGateway.error = EndPairingException(EndPairingFailure.unavailable);
      await pumpUs(tester);
      await openLeaveNow(tester);
      await confirmLeave(tester);
      await tester.pumpAndSettle();
      expect(find.text('This needs our server'), findsOneWidget);
      await tester.tap(find.byKey(const Key('leave-use-14-days')));
      await tester.pumpAndSettle();
      expect((await current(rig)).requestedBy, pAsha);
      expect(find.text('end'), findsOneWidget);
    });
  });

  group('pairing ended', () {
    testWidgets('shown once, then cleared, then pairing again', (tester) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await rig.db.collection('users').doc(pAsha).set({
        'displayName': 'Asha',
        'coupleId': null,
        'profileComplete': true,
        'setupComplete': true,
        'pairingEndedAt': Timestamp.fromDate(t0),
        'pairingEndedHow': 'agreed',
      });
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            ...rig.overrides(pAsha),
            authStateProvider.overrideWith(
              (ref) => Stream.value(_FakeUser(pAsha)),
            ),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const AuthGate()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your pairing has ended'), findsOneWidget);
      expect(find.textContaining('You decided this together'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pairing-ended-continue')));
      await tester.pumpAndSettle();
      final data = (await rig.db.collection('users').doc(pAsha).get()).data()!;
      expect(data.containsKey('pairingEndedAt'), isFalse);
      expect(find.text('Connect with your partner'), findsOneWidget);
    });

    testWidgets('after "leave now" the other one only sees it ended', (
      tester,
    ) async {
      await rig.db.collection('users').doc(pRavi).set({
        'displayName': 'Ravi',
        'coupleId': null,
        'profileComplete': true,
        'pairingEndedAt': Timestamp.fromDate(t0),
        'pairingEndedHow': 'leftNow',
      });
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            ...rig.overrides(pRavi),
            authStateProvider.overrideWith(
              (ref) => Stream.value(_FakeUser(pRavi)),
            ),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const AuthGate()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('This pairing has ended'), findsOneWidget);
      expect(find.textContaining('safe'), findsNothing);
      expect(find.textContaining('leave'), findsNothing);
    });
  });

  group('muted partner', () {
    Future<void> ring(PairingRig rig) => CallService(db: rig.db).startCall(
      coupleId: pCouple,
      callerId: pRavi,
      calleeId: pAsha,
      type: CallType.voice,
    );

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: rig.overrides(pAsha),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const PairingReady(
              uid: pAsha,
              child: IncomingCallListener(child: Scaffold(body: Text('home'))),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<String?> callStatus() async =>
        (await rig.couple.collection('call').doc('current').get())
                .data()?['status']
            as String?;

    testWidgets('their call is not rung and ends as missed', (tester) async {
      await rig.seedCouple(
        separation: rig.separationMap(),
        ashaExtra: {'mutePartner': true},
      );
      await pump(tester);
      await ring(rig);
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(find.text('Decline'), findsNothing);
      expect(await callStatus(), 'missed');
    });

    testWidgets('unmuted, it rings as usual', (tester) async {
      await rig.seedCouple();
      await pump(tester);
      await ring(rig);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Decline'), findsOneWidget);
      expect(await callStatus(), 'ringing');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
    });
  });
}

/// Like the shell: checks the separation once on open.
class _Finalizes extends ConsumerStatefulWidget {
  const _Finalizes({required this.child});

  final Widget child;

  @override
  ConsumerState<_Finalizes> createState() => _FinalizesState();
}

class _FinalizesState extends ConsumerState<_Finalizes> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(separationFinalizerProvider.notifier).check();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(separationFinalizerProvider);
    return widget.child;
  }
}
