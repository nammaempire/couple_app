import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/core/theme/app_theme.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/couple/data/couple_service.dart';
import 'package:couple_app/features/couple/data/pair_request_service.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/models/pair_request.dart';
import 'package:couple_app/features/onboarding/screens/pairing_screen.dart';
import 'package:couple_app/features/onboarding/widgets/pair_request_cards.dart';

import 'pairing_fakes.dart';

/// Asha and Ravi, both signed up and unpaired; Ravi has verified his
/// number.
Future<void> seedUnpaired(PairingRig rig, {bool raviIndexed = true}) async {
  for (final (uid, name, phone) in [
    (pAsha, 'Asha', ashaPhone),
    (pRavi, 'Ravi', raviPhone),
  ]) {
    await rig.db.collection('users').doc(uid).set({
      'displayName': name,
      'coupleId': null,
      'profileComplete': true,
      'setupComplete': false,
      'phone': phone,
    });
  }
  await rig.db.collection('phoneIndex').doc(ashaPhone).set({
    'uid': pAsha,
    'createdAt': FieldValue.serverTimestamp(),
  });
  if (raviIndexed) {
    await rig.db.collection('phoneIndex').doc(raviPhone).set({
      'uid': pRavi,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

Future<AppUser> user(PairingRig rig, String uid) async =>
    AppUser.fromDoc(await rig.db.collection('users').doc(uid).get());

Future<List<PairRequest>> allRequests(PairingRig rig) async =>
    (await rig.db.collection('pairRequests').get()).docs
        .map(PairRequest.fromDoc)
        .toList();

void main() {
  late PairingRig rig;

  setUp(() => rig = PairingRig());

  group('PairRequestService', () {
    test('a number nobody verified: "not joined", nothing written', () async {
      await seedUnpaired(rig, raviIndexed: false);
      final outcome = await rig.requests.requestByNumber(
        me: await user(rig, pAsha),
        toPhone: raviPhone,
      );
      expect(outcome, isA<PairByNumberNotJoined>());
      expect(await allRequests(rig), isEmpty);
      expect((await user(rig, pAsha)).coupleId, isNull);
    });

    test('found: makes Asha\'s space of one, then the request', () async {
      await seedUnpaired(rig);
      final outcome = await rig.requests.requestByNumber(
        me: await user(rig, pAsha),
        toPhone: raviPhone,
      );
      expect(outcome, isA<PairByNumberSent>());

      final asha = await user(rig, pAsha);
      expect(asha.coupleId, isNotNull);
      final couple = Couple.fromDoc(
        await rig.db.collection('couples').doc(asha.coupleId).get(),
      );
      expect(couple.memberIds, [pAsha]);

      final doc = (await rig.db.collection('pairRequests').get()).docs.single;
      expect(doc.data().keys.toSet(), {
        'fromUid',
        'fromName',
        'fromPhone',
        'toUid',
        'toPhone',
        'coupleId',
        'inviteCode',
        'status',
        'createdAt',
      });
      final r = PairRequest.fromDoc(doc);
      expect(r.fromUid, pAsha);
      expect(r.fromName, 'Asha');
      expect(r.fromPhone, ashaPhone);
      expect(r.toUid, pRavi);
      expect(r.toPhone, raviPhone);
      expect(r.coupleId, couple.id);
      expect(r.inviteCode, couple.inviteCode);
      expect(r.status, PairRequestStatus.pending);
      expect(doc.data()['createdAt'], isA<Timestamp>());
    });

    test('uses an existing space of one, and never asks twice', () async {
      await seedUnpaired(rig);
      final mine = await rig.couples.createCouple(pAsha, inviterName: 'Asha');
      final me = await user(rig, pAsha);
      await rig.requests.requestByNumber(
        me: me,
        toPhone: raviPhone,
        myCouple: mine,
      );
      await rig.requests.requestByNumber(
        me: me,
        toPhone: raviPhone,
        myCouple: mine,
      );
      final requests = await allRequests(rig);
      expect(requests, hasLength(1));
      expect(requests.single.coupleId, mine.id);
      expect((await rig.db.collection('couples').get()).docs, hasLength(1));
    });

    test('your own number is refused', () async {
      await seedUnpaired(rig);
      expect(
        () async => rig.requests.requestByNumber(
          me: await user(rig, pAsha),
          toPhone: ashaPhone,
        ),
        throwsA(isA<PairingException>()),
      );
    });

    test('anything else only ever says "Couldn\'t pair"', () async {
      await seedUnpaired(rig);
      // Asha is already in a complete couple: she has no space to offer.
      await rig.db.collection('users').doc(pAsha).update({'coupleId': 'x'});
      await expectLater(
        rig.requests.requestByNumber(
          me: await user(rig, pAsha),
          toPhone: raviPhone,
        ),
        throwsA(
          isA<PairingException>().having(
            (e) => e.message,
            'message',
            PairRequestService.couldNotPair,
          ),
        ),
      );
    });

    Future<PairRequest> sent() async {
      await seedUnpaired(rig);
      await rig.requests.requestByNumber(
        me: await user(rig, pAsha),
        toPhone: raviPhone,
      );
      return (await allRequests(rig)).single;
    }

    test('accept joins with the invite and marks it accepted', () async {
      final r = await sent();
      final incoming = await rig.requests.watchIncoming(pRavi).first;
      expect(incoming.single.id, r.id);

      await rig.requests.accept(uid: pRavi, request: r);

      final couple = await rig.db.collection('couples').doc(r.coupleId).get();
      expect(couple.data()!['memberIds'], [pAsha, pRavi]);
      expect((await user(rig, pRavi)).coupleId, r.coupleId);
      final invite = await rig.db.collection('invites').doc(r.inviteCode).get();
      expect(invite.data()!['used'], isTrue);
      expect(invite.data()!['usedBy'], pRavi);
      expect(
        (await allRequests(rig)).single.status,
        PairRequestStatus.accepted,
      );
      expect(await rig.requests.watchIncoming(pRavi).first, isEmpty);
    });

    test('accept gives up Ravi\'s own waiting space first', () async {
      final r = await sent();
      final own = await rig.couples.createCouple(pRavi, inviterName: 'Ravi');
      await rig.requests.accept(uid: pRavi, request: r, myCouple: own);
      expect(
        (await rig.db.collection('couples').doc(own.id).get()).exists,
        isFalse,
      );
      expect((await user(rig, pRavi)).coupleId, r.coupleId);
    });

    test('only the owner hears "already paired"', () async {
      final r = await sent();
      const paired = Couple(
        id: 'other',
        inviteCode: 'ZZZZZZ',
        memberIds: [pRavi, 'someone'],
      );
      await expectLater(
        rig.requests.accept(uid: pRavi, request: r, myCouple: paired),
        throwsA(
          isA<PairingException>().having(
            (e) => e.message,
            'message',
            PairRequestService.alreadyPaired,
          ),
        ),
      );
      expect((await allRequests(rig)).single.status, PairRequestStatus.pending);
    });

    test('decline and cancel only move the status', () async {
      final r = await sent();
      await rig.requests.decline(r);
      expect(
        (await allRequests(rig)).single.status,
        PairRequestStatus.declined,
      );

      await rig.db.collection('pairRequests').doc(r.id).update({
        'status': 'pending',
      });
      await rig.requests.cancel(r);
      final after = (await allRequests(rig)).single;
      expect(after.status, PairRequestStatus.cancelled);
      expect(after.toUid, pRavi);
    });
  });

  group('screens', () {
    Future<void> pumpPairing(WidgetTester tester, String uid) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final me = await user(rig, uid);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: rig.overrides(uid),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: PairingScreen(uid: uid, me: me),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> requestNumber(WidgetTester tester, String number) async {
      await tester.tap(find.text('Pair with their mobile number'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('phone-number-field')),
        number,
      );
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();
    }

    testWidgets('not joined: offers the invite in the share sheet', (
      tester,
    ) async {
      await seedUnpaired(rig, raviIndexed: false);
      await pumpPairing(tester, pAsha);
      await requestNumber(tester, '98123 43210');

      expect(
        find.text('They haven\'t joined yet — share your invite instead'),
        findsOneWidget,
      );
      await tester.tap(find.text('Share your invite'));
      await tester.pumpAndSettle();

      final asha = await user(rig, pAsha);
      final couple = await rig.db
          .collection('couples')
          .doc(asha.coupleId)
          .get();
      final code = couple.data()!['inviteCode'] as String;
      expect(rig.shared.single, contains(code));
    });

    testWidgets('found: sends the request', (tester) async {
      await seedUnpaired(rig);
      await pumpPairing(tester, pAsha);
      await requestNumber(tester, '98123 43210');
      expect(find.text('Request sent'), findsOneWidget);
      expect((await allRequests(rig)).single.toUid, pRavi);
    });

    testWidgets('a failure shows only the generic message', (tester) async {
      await seedUnpaired(rig);
      await rig.db.collection('users').doc(pAsha).update({'coupleId': 'x'});
      // The service finds her already in a space she can't offer.
      await pumpPairing(tester, pAsha);
      await requestNumber(tester, '98123 43210');
      expect(find.text(PairRequestService.couldNotPair), findsOneWidget);
    });

    testWidgets('incoming: shows who, with a masked number, and accepts', (
      tester,
    ) async {
      await seedUnpaired(rig);
      await rig.requests.requestByNumber(
        me: await user(rig, pAsha),
        toPhone: raviPhone,
      );
      await pumpPairing(tester, pRavi);

      expect(
        find.text('Asha (+91 98•••• 3210) wants to pair with you'),
        findsOneWidget,
      );
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      final r = (await allRequests(rig)).single;
      expect(r.status, PairRequestStatus.accepted);
      expect((await user(rig, pRavi)).coupleId, r.coupleId);
    });

    testWidgets('incoming: decline hides it', (tester) async {
      await seedUnpaired(rig);
      await rig.requests.requestByNumber(
        me: await user(rig, pAsha),
        toPhone: raviPhone,
      );
      await pumpPairing(tester, pRavi);
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      expect(find.textContaining('wants to pair with you'), findsNothing);
      expect(
        (await allRequests(rig)).single.status,
        PairRequestStatus.declined,
      );
    });

    testWidgets('outgoing: waiting with Cancel, then the generic message', (
      tester,
    ) async {
      await seedUnpaired(rig);
      await rig.requests.requestByNumber(
        me: await user(rig, pAsha),
        toPhone: raviPhone,
      );
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: rig.overrides(pAsha),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: OutgoingPairRequestCard(uid: pAsha)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Waiting for +91 98123 43210 to accept'),
        findsOneWidget,
      );

      // Ravi declines (or couldn't accept): Asha learns nothing more.
      final r = (await allRequests(rig)).single;
      await rig.requests.decline(r);
      await tester.pumpAndSettle();
      expect(find.text(PairRequestService.couldNotPair), findsOneWidget);
      expect(find.textContaining('paired'), findsNothing);

      // Cancel a fresh one.
      await rig.db.collection('pairRequests').doc(r.id).update({
        'status': 'pending',
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        (await allRequests(rig)).single.status,
        PairRequestStatus.cancelled,
      );
      expect(find.textContaining('Waiting for'), findsNothing);
    });
  });
}
