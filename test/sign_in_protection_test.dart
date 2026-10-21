import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/core/theme/app_theme.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/auth/screens/auth_gate.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/security/data/account_reauth.dart';
import 'package:couple_app/features/security/device_trust_controller.dart';
import 'package:couple_app/features/security/models/device_check.dart';
import 'package:couple_app/features/security/models/security_event.dart';
import 'package:couple_app/features/security/providers/security_providers.dart';
import 'package:couple_app/features/security/screens/confirm_new_phone_screen.dart';
import 'package:couple_app/features/security/screens/security_screen.dart';
import 'package:couple_app/features/security/widgets/device_check_listener.dart';
import 'package:couple_app/features/security/widgets/security_banners.dart';
import 'package:couple_app/features/security/widgets/us_security_row.dart';
import 'package:couple_app/features/shell/main_shell.dart';

import 'pairing_fakes.dart';

void main() {
  late PairingRig rig;
  late FakePhoneAuthService auth;

  setUp(() {
    rig = PairingRig();
    auth = FakePhoneAuthService(pAsha);
  });

  CollectionReference<Map<String, dynamic>> devices(String uid) =>
      rig.db.collection('users').doc(uid).collection('devices');

  CollectionReference<Map<String, dynamic>> events(String uid) =>
      rig.db.collection('users').doc(uid).collection('securityEvents');

  CollectionReference<Map<String, dynamic>> checks() =>
      rig.couple.collection('deviceChecks');

  Future<String> myDeviceId() => rig.identity.deviceId(pAsha);

  /// A phone the account already knows, last seen [ago] before the clock.
  Future<void> seedDevice(
    String id, {
    String uid = pAsha,
    String name = 'Pixel 7',
    String via = 'first',
    Duration ago = const Duration(hours: 2),
  }) => devices(uid).doc(id).set({
    'name': name,
    'addedAt': Timestamp.fromDate(rig.now.subtract(const Duration(days: 400))),
    'lastSeenAt': Timestamp.fromDate(rig.now.subtract(ago)),
    'via': via,
  });

  Future<DeviceTrust> evaluate() async {
    final c = ProviderContainer.test(overrides: rig.overrides(pAsha));
    final sub = c.listen(deviceTrustProvider(pAsha), (_, _) {});
    final trust = await c.read(deviceTrustProvider(pAsha).future);
    sub.close();
    return trust;
  }

  group('deciding', () {
    test('the first phone of an account is trusted and recorded', () async {
      await rig.seedCouple();
      final trust = await evaluate();
      expect(trust.trusted, isTrue);

      final id = await myDeviceId();
      final doc = await devices(pAsha).doc(id).get();
      expect(doc.data()!.keys.toSet(), {
        'name',
        'addedAt',
        'lastSeenAt',
        'via',
      });
      expect(doc.data()!['name'], 'Pixel 9');
      expect(doc.data()!['via'], 'first');
      expect(doc.data()!['addedAt'], isA<Timestamp>());
      expect(doc.data()!['lastSeenAt'], isA<Timestamp>());
      // No notice for the first phone.
      expect((await events(pAsha).get()).docs, isEmpty);
    });

    test('the device id is the vault\'s, kept in secure storage', () async {
      final id = await myDeviceId();
      expect(id, hasLength(20));
      expect((await rig.keystore.loadIdentity(pAsha))!.deviceId, id);
      expect(await rig.identity.deviceId(pAsha), id);
    });

    test('a known phone is not asked again; seen at most once a day', () async {
      await rig.seedCouple();
      final id = await myDeviceId();
      await seedDevice(id, ago: const Duration(hours: 3));
      await seedDevice('old', ago: const Duration(days: 30));

      expect((await evaluate()).trusted, isTrue);
      var seen = (await devices(pAsha).doc(id).get()).data()!['lastSeenAt'];
      expect(
        (seen as Timestamp).toDate(),
        rig.now.subtract(const Duration(hours: 3)),
      );

      // Signing out and back in on the same phone.
      await devices(pAsha).doc(id).update({
        'lastSeenAt': Timestamp.fromDate(
          rig.now.subtract(const Duration(days: 2)),
        ),
      });
      expect((await evaluate()).trusted, isTrue);
      await Future<void>.delayed(Duration.zero);
      final doc = (await devices(pAsha).doc(id).get()).data()!;
      seen = doc['lastSeenAt'] as Timestamp;
      expect(
        seen.toDate().isAfter(rig.now.subtract(const Duration(days: 1))),
        isTrue,
      );
      expect(doc['via'], 'first');
      expect((await devices(pAsha).get()).docs, hasLength(2));
    });

    test('a new phone on an account with phones is asked', () async {
      await rig.seedCouple();
      await seedDevice('old');
      final trust = await evaluate();
      expect(trust.trusted, isFalse);
      expect(trust.reason, NewPhoneReason.newPhone);
      expect(trust.known, isFalse);
      expect(trust.partner!.uid, pRavi);
      expect(trust.partner!.name, 'Ravi');
      expect(trust.onlyWait, isFalse);
      // Nothing recorded until it passes.
      expect((await devices(pAsha).get()).docs, hasLength(1));
    });

    test('180 days with no phone seen asks even a known phone', () async {
      await rig.seedCouple();
      final id = await myDeviceId();
      await seedDevice(id, ago: const Duration(days: 181));
      await seedDevice('old', ago: const Duration(days: 200));
      final trust = await evaluate();
      expect(trust.trusted, isFalse);
      expect(trust.reason, NewPhoneReason.inactive);
      expect(trust.known, isTrue);

      // 179 days is fine.
      await seedDevice('old', ago: const Duration(days: 179));
      expect((await evaluate()).trusted, isTrue);
    });

    test('unpaired with no email: only the wait', () async {
      await rig.db.collection('users').doc(pAsha).set({
        'displayName': 'Asha',
        'coupleId': null,
        'profileComplete': true,
      });
      await seedDevice('old');
      final trust = await evaluate();
      expect(trust.partner, isNull);
      expect(trust.onlyWait, isTrue);

      rig.reauth.current = const ReauthOptions(passwordEmail: 'a@x.com');
      expect((await evaluate()).onlyWait, isFalse);
    });

    test('a separation in progress still has the partner', () async {
      await rig.seedCouple(separation: rig.separationMap(by: pRavi));
      await seedDevice('old');
      expect((await evaluate()).partner!.uid, pRavi);
    });
  });

  group('the gate', () {
    var coupleReads = 0;

    List<Override> gateOverrides() => [
      ...rig.overrides(pAsha, auth: auth),
      authStateProvider.overrideWith((ref) => Stream.value(FakeUser(pAsha))),
      coupleProvider.overrideWith((ref) {
        coupleReads++;
        return rig.db
            .collection('couples')
            .doc(ref.watch(currentCoupleIdProvider))
            .snapshots()
            .map((d) => d.exists ? Couple.fromDoc(d) : null);
      }),
    ];

    Future<void> pumpGate(WidgetTester tester) async {
      coupleReads = 0;
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: gateOverrides(),
          child: MaterialApp(theme: AppTheme.light(), home: const AuthGate()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows "Confirm it\'s you" and reads no couple data', (
      tester,
    ) async {
      await rig.seedCouple(ashaExtra: {'setupComplete': false});
      await seedDevice('old');
      await pumpGate(tester);

      expect(find.byType(ConfirmNewPhoneScreen), findsOneWidget);
      expect(find.text('Confirm it\'s you'), findsOneWidget);
      expect(find.text(newPhoneWhy), findsOneWidget);
      expect(find.text(newPhoneReinstallNote), findsOneWidget);
      expect(find.text('Ask Ravi'), findsOneWidget);
      // No email linked: no password or Google option.
      expect(find.byKey(const Key('new-phone-password')), findsNothing);
      expect(find.byKey(const Key('new-phone-google')), findsNothing);
      expect(find.byType(MainShell), findsNothing);
      expect(coupleReads, 0);
    });

    testWidgets('a known phone goes straight in', (tester) async {
      await rig.seedCouple(ashaExtra: {'setupComplete': false});
      await seedDevice(await myDeviceId());
      await pumpGate(tester);
      expect(find.byType(ConfirmNewPhoneScreen), findsNothing);
      expect(find.text('Your anniversary'), findsOneWidget);
      expect(coupleReads, greaterThan(0));
    });

    testWidgets('partner approves: the phone is added and the app opens', (
      tester,
    ) async {
      await rig.seedCouple(ashaExtra: {'setupComplete': false});
      await seedDevice('old');
      await pumpGate(tester);

      await tester.tap(find.byKey(const Key('new-phone-ask-partner')));
      await tester.pumpAndSettle();
      expect(find.text('Waiting for Ravi'), findsOneWidget);

      final check = (await checks().get()).docs.single;
      final data = check.data();
      final id = await myDeviceId();
      expect(data.keys.toSet(), {
        'uid',
        'deviceId',
        'deviceName',
        'createdAt',
        'status',
        'code',
      });
      expect(data['uid'], pAsha);
      expect(data['deviceId'], id);
      expect(data['deviceName'], 'Pixel 9');
      expect(data['status'], 'pending');
      final code = data['code'] as int;
      expect(code, inInclusiveRange(10, 99));
      expect(find.text('$code'), findsOneWidget);
      expect(coupleReads, 0);

      // Ravi says yes on his phone.
      await rig.trust.decideCheck(
        cid: pCouple,
        check: DeviceCheck.fromDoc(check),
        decidedBy: pRavi,
        approved: true,
      );
      await tester.pumpAndSettle();

      expect(find.byType(ConfirmNewPhoneScreen), findsNothing);
      expect(find.text('Your anniversary'), findsOneWidget);
      expect(coupleReads, greaterThan(0));
      final device = (await devices(pAsha).doc(id).get()).data()!;
      expect(device['via'], 'partner');
      expect(device['name'], 'Pixel 9');
      // The check is cleaned up; the owner's other phones hear about it.
      expect((await checks().get()).docs, isEmpty);
      final notice = (await events(pAsha).get()).docs.single;
      expect(notice.id, startsWith('approved_${id}_'));
      expect(notice.data()['type'], 'newPhoneApproved');
      expect(notice.data()['deviceName'], 'Pixel 9');
    });

    testWidgets('partner says no: the phone is told and signs out', (
      tester,
    ) async {
      await rig.seedCouple();
      await seedDevice('old');
      await pumpGate(tester);

      await tester.tap(find.byKey(const Key('new-phone-ask-partner')));
      await tester.pumpAndSettle();
      final check = (await checks().get()).docs.single;
      await rig.trust.decideCheck(
        cid: pCouple,
        check: DeviceCheck.fromDoc(check),
        decidedBy: pRavi,
        approved: false,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Your partner didn\'t recognise this sign-in'),
        findsOneWidget,
      );
      expect(find.byType(MainShell), findsNothing);
      // Ravi's "no" left a gentle notice for Asha's real phones.
      final notice = (await events(pAsha).get()).docs.single.data();
      expect(notice['type'], 'newPhoneRejected');
      expect(notice['deviceName'], 'Pixel 9');

      await tester.tap(find.byKey(const Key('new-phone-rejected-sign-out')));
      await tester.pumpAndSettle();
      expect(auth.signOutCalls, 1);
      expect((await checks().get()).docs, isEmpty);
      expect((await devices(pAsha).get()).docs, hasLength(1));
      expect(coupleReads, 0);
    });

    testWidgets('picks up its earlier check after a restart', (tester) async {
      await rig.seedCouple();
      await seedDevice('old');
      await checks().doc('k1').set({
        'uid': pAsha,
        'deviceId': await myDeviceId(),
        'deviceName': 'Pixel 9',
        'createdAt': Timestamp.fromDate(rig.now),
        'status': 'pending',
        'code': 47,
      });
      await pumpGate(tester);
      expect(find.text('Waiting for Ravi'), findsOneWidget);
      expect(find.text('47'), findsOneWidget);

      // Giving up removes it, so Ravi isn't asked.
      await tester.tap(find.byKey(const Key('new-phone-cancel-partner')));
      await tester.pumpAndSettle();
      expect(find.text('Confirm it\'s you'), findsOneWidget);
      expect((await checks().get()).docs, isEmpty);
    });

    testWidgets('the account password confirms it', (tester) async {
      await rig.seedCouple(ashaExtra: {'setupComplete': false});
      await seedDevice('old');
      rig.reauth.current = const ReauthOptions(
        passwordEmail: 'asha@example.com',
      );
      await pumpGate(tester);

      expect(find.text('For asha@example.com'), findsOneWidget);
      await tester.tap(find.byKey(const Key('new-phone-password')));
      await tester.pumpAndSettle();
      expect(find.text('Enter your password'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('new-phone-password-field')),
        'nope',
      );
      await tester.tap(find.byKey(const Key('new-phone-password-confirm')));
      await tester.pumpAndSettle();
      expect(find.text(ReauthError.wrongPassword.message), findsOneWidget);
      expect((await devices(pAsha).get()).docs, hasLength(1));

      await tester.tap(find.text('Forgot it? Email me a reset link'));
      await tester.pumpAndSettle();
      expect(rig.reauth.resets, 1);
      expect(find.text('Reset link sent to asha@example.com'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('new-phone-password-field')),
        'secret',
      );
      await tester.tap(find.byKey(const Key('new-phone-password-confirm')));
      await tester.pumpAndSettle();

      expect(rig.reauth.passwords, ['nope', 'secret']);
      expect(find.text('Your anniversary'), findsOneWidget);
      final device = (await devices(
        pAsha,
      ).doc(await myDeviceId()).get()).data()!;
      expect(device['via'], 'email');
    });

    testWidgets('the Google account confirms it; a wrong one is refused', (
      tester,
    ) async {
      await rig.seedCouple(ashaExtra: {'setupComplete': false});
      await seedDevice('old');
      rig.reauth.current = const ReauthOptions(googleEmail: 'asha@gmail.com');
      rig.reauth.googleError = ReauthError.wrongAccount;
      await pumpGate(tester);

      await tester.tap(find.byKey(const Key('new-phone-google')));
      await tester.pumpAndSettle();
      expect(find.text(ReauthError.wrongAccount.message), findsOneWidget);

      rig.reauth.googleError = null;
      await tester.tap(find.byKey(const Key('new-phone-google')));
      await tester.pumpAndSettle();
      expect(rig.reauth.googleCalls, 2);
      expect(find.text('Your anniversary'), findsOneWidget);
      final device = (await devices(
        pAsha,
      ).doc(await myDeviceId()).get()).data()!;
      expect(device['via'], 'email');
    });

    testWidgets('the 180-day check passes by touching the known phone', (
      tester,
    ) async {
      await rig.seedCouple(ashaExtra: {'setupComplete': false});
      final id = await myDeviceId();
      await seedDevice(id, ago: const Duration(days: 190));
      rig.reauth.current = const ReauthOptions(passwordEmail: 'a@x.com');
      await pumpGate(tester);
      expect(find.byKey(const Key('new-phone-reason')), findsOneWidget);
      expect(find.textContaining('been a while'), findsOneWidget);

      await tester.tap(find.byKey(const Key('new-phone-password')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('new-phone-password-field')),
        'secret',
      );
      await tester.tap(find.byKey(const Key('new-phone-password-confirm')));
      await tester.pumpAndSettle();
      final device = (await devices(pAsha).doc(id).get()).data()!;
      // Only lastSeenAt changes on an existing phone.
      expect(device['via'], 'first');
      expect(
        (device['lastSeenAt'] as Timestamp).toDate().isAfter(
          rig.now.subtract(const Duration(days: 1)),
        ),
        isTrue,
      );
    });

    group('the 7-day wait', () {
      Future<void> unpaired() async {
        await rig.db.collection('users').doc(pAsha).set({
          'displayName': 'Asha',
          'coupleId': null,
          'profileComplete': true,
          'setupComplete': true,
        });
        await seedDevice('old');
      }

      testWidgets('counts down, then lets the phone in', (tester) async {
        await unpaired();
        await pumpGate(tester);
        final id = await myDeviceId();

        expect(find.text('One week, to be safe'), findsOneWidget);
        expect(find.textContaining('Add a recovery email next time'), findsOne);
        // The wait began, and the owner's other phones were told.
        final wait = await events(pAsha).doc('wait_$id').get();
        expect(wait.data()!['type'], 'newPhoneWaiting');
        expect(wait.data()!['deviceName'], 'Pixel 9');
        expect(wait.data()!.keys.toSet(), {'type', 'deviceName', 'at'});

        // Three days in.
        await events(pAsha).doc('wait_$id').update({
          'at': Timestamp.fromDate(rig.now.subtract(const Duration(days: 3))),
        });
        await tester.pumpAndSettle();
        expect(find.text('4 days'), findsOneWidget);
        expect(find.byKey(const Key('new-phone-wait-continue')), findsNothing);

        rig.now = rig.now.add(const Duration(days: 3, hours: 22, minutes: 30));
        await tester.pump(const Duration(minutes: 1));
        expect(find.text('1 hour 30 min'), findsOneWidget);

        rig.now = rig.now.add(const Duration(hours: 2));
        await tester.pump(const Duration(minutes: 1));
        expect(find.text('Thanks for waiting'), findsOneWidget);
        await tester.tap(find.byKey(const Key('new-phone-wait-continue')));
        await tester.pumpAndSettle();

        expect(find.byType(ConfirmNewPhoneScreen), findsNothing);
        expect(find.text('Connect with your partner'), findsOneWidget);
        final device = (await devices(pAsha).doc(id).get()).data()!;
        expect(device['via'], 'wait');
        expect((await events(pAsha).doc('wait_$id').get()).exists, isFalse);
      });

      testWidgets('"It wasn\'t me" pauses it, even after 7 days', (
        tester,
      ) async {
        await unpaired();
        final id = await myDeviceId();
        await events(pAsha).doc('wait_$id').set({
          'type': 'newPhoneWaiting',
          'deviceName': 'Pixel 9',
          'at': Timestamp.fromDate(rig.now.subtract(const Duration(days: 8))),
        });
        await rig.db.collection('users').doc(pAsha).update({
          'blockNewPhoneUntil': Timestamp.fromDate(
            rig.now.add(const Duration(days: 20)),
          ),
        });
        await pumpGate(tester);

        expect(find.text('Waiting is paused'), findsOneWidget);
        expect(find.byKey(const Key('new-phone-wait-continue')), findsNothing);

        // Once the pause is over, the finished wait lets it in.
        rig.now = rig.now.add(const Duration(days: 21));
        await tester.pump(const Duration(minutes: 1));
        expect(find.byKey(const Key('new-phone-wait-continue')), findsOne);
      });

      test('labels', () {
        expect(
          waitLeftLabel(const Duration(days: 6, hours: 23)),
          '6 days 23 hours',
        );
        expect(waitLeftLabel(const Duration(days: 1)), '1 day');
        expect(
          waitLeftLabel(const Duration(hours: 5, minutes: 12)),
          '5 hours 12 min',
        );
        expect(waitLeftLabel(const Duration(seconds: 20)), '1 min');
      });
    });
  });

  group('the partner\'s phone', () {
    Future<void> pumpRavi(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: rig.overrides(pRavi),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: PairingReady(
              uid: pRavi,
              child: DeviceCheckListener(child: Scaffold(body: child)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> seedCheck() => checks().doc('k1').set({
      'uid': pAsha,
      'deviceId': 'new',
      'deviceName': 'Pixel 9',
      'createdAt': Timestamp.fromDate(rig.now),
      'status': 'pending',
      'code': 47,
    });

    testWidgets('asks, and "Yes" approves', (tester) async {
      await rig.seedCouple();
      await seedCheck();
      await pumpRavi(tester, const SecurityBanners());

      expect(find.text('Is this really Asha?'), findsOneWidget);
      expect(
        find.textContaining('Asha signed in on a new phone (Pixel 9)'),
        findsWidgets,
      );
      expect(find.byKey(const Key('device-check-code')), findsOneWidget);
      expect(find.text('47'), findsOneWidget);

      await tester.tap(find.byKey(const Key('device-check-yes')));
      await tester.pumpAndSettle();
      final data = (await checks().doc('k1').get()).data()!;
      expect(data['status'], 'approved');
      expect(data['decidedBy'], pRavi);
      expect(data['decidedAt'], isA<Timestamp>());
      expect((await events(pAsha).get()).docs, isEmpty);
      expect(find.text('Is this really Asha?'), findsNothing);
      expect(find.byKey(const Key('device-check-banner')), findsNothing);
    });

    testWidgets('"No" rejects and tells Asha\'s other phones', (tester) async {
      await rig.seedCouple();
      await seedCheck();
      await pumpRavi(tester, const SizedBox());
      await tester.tap(find.byKey(const Key('device-check-no')));
      await tester.pumpAndSettle();
      final data = (await checks().doc('k1').get()).data()!;
      expect(data['status'], 'rejected');
      expect(data['decidedBy'], pRavi);
      final notice = (await events(pAsha).get()).docs.single.data();
      expect(notice.keys.toSet(), {'type', 'deviceName', 'at'});
      expect(notice['type'], 'newPhoneRejected');
    });

    testWidgets('"Decide later" leaves the banner; old checks are ignored', (
      tester,
    ) async {
      await rig.seedCouple();
      await seedCheck();
      await checks().doc('old').set({
        'uid': pAsha,
        'deviceId': 'older',
        'deviceName': 'Moto',
        'createdAt': Timestamp.fromDate(
          rig.now.subtract(const Duration(days: 2)),
        ),
        'status': 'pending',
        'code': 12,
      });
      await pumpRavi(tester, const SecurityBanners());
      await tester.tap(find.text('Decide later'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-check-banner')), findsOneWidget);
      expect(find.textContaining('Moto'), findsNothing);

      await tester.tap(find.byKey(const Key('device-check-review')));
      await tester.pumpAndSettle();
      expect(find.text('Is this really Asha?'), findsOneWidget);
    });

    testWidgets('the dialog closes if the new phone gives up', (tester) async {
      await rig.seedCouple();
      await seedCheck();
      await pumpRavi(tester, const SizedBox());
      expect(find.text('Is this really Asha?'), findsOneWidget);
      await checks().doc('k1').delete();
      await tester.pumpAndSettle();
      expect(find.text('Is this really Asha?'), findsNothing);
    });
  });

  group('the owner\'s other phone', () {
    Future<void> pumpAsha(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: rig.overrides(pAsha),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: PairingReady(uid: pAsha, child: child),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('"It wasn\'t me" blocks waiting phones for 30 days', (
      tester,
    ) async {
      await rig.seedCouple();
      await events(pAsha).doc('wait_new').set({
        'type': 'newPhoneWaiting',
        'deviceName': 'Galaxy A15',
        'at': Timestamp.fromDate(rig.now),
      });
      await pumpAsha(tester, const Scaffold(body: SecurityBanners()));
      expect(find.byKey(const Key('security-notice-waiting')), findsOneWidget);
      expect(find.textContaining('Galaxy A15'), findsOneWidget);

      await tester.tap(find.byKey(const Key('security-notice-wasnt-me')));
      await tester.pumpAndSettle();
      final user = (await rig.db.collection('users').doc(pAsha).get()).data()!;
      expect(
        (user['blockNewPhoneUntil'] as Timestamp).toDate(),
        rig.now.add(const Duration(days: 30)),
      );
      expect((await events(pAsha).doc('wait_new').get()).exists, isFalse);
      expect(find.byKey(const Key('security-notice-waiting')), findsNothing);
    });

    testWidgets('a rejected sign-in is a gentle notice; OK clears it', (
      tester,
    ) async {
      await rig.seedCouple();
      await events(pAsha).doc('e1').set({
        'type': 'newPhoneRejected',
        'deviceName': 'Galaxy A15',
        'at': Timestamp.fromDate(rig.now),
      });
      await pumpAsha(tester, const Scaffold(body: SecurityBanners()));
      expect(find.textContaining('Ravi didn\'t recognise it'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect((await events(pAsha).get()).docs, isEmpty);
    });

    testWidgets('notices about this phone itself are not shown here', (
      tester,
    ) async {
      await rig.seedCouple();
      final id = await myDeviceId();
      await events(pAsha).doc('approved_${id}_1').set({
        'type': 'newPhoneApproved',
        'deviceName': 'Pixel 9',
        'at': Timestamp.fromDate(rig.now),
      });
      await pumpAsha(tester, const Scaffold(body: SecurityBanners()));
      expect(find.byKey(const Key('security-notice-approved')), findsNothing);
    });
  });

  group('SecurityScreen', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: rig.overrides(pAsha),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: PairingReady(
              uid: pAsha,
              child: Scaffold(
                body: ListView(children: const [UsSecurityRow()]),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('us-security-row')));
      await tester.pumpAndSettle();
    }

    testWidgets('lists phones; others can be removed, this one can\'t', (
      tester,
    ) async {
      await rig.seedCouple();
      final id = await myDeviceId();
      await seedDevice(id, name: 'Pixel 9', ago: Duration.zero);
      await seedDevice(
        'old',
        name: 'Pixel 7',
        via: 'partner',
        ago: const Duration(days: 3),
      );
      await pumpScreen(tester);

      expect(find.byType(SecurityScreen), findsOneWidget);
      expect(find.text('Pixel 9 · this phone'), findsOneWidget);
      expect(
        find.text('Last seen 3 days ago · Approved by your partner'),
        findsOneWidget,
      );
      expect(find.byKey(Key('security-remove-$id')), findsNothing);

      await tester.tap(find.byKey(const Key('security-remove-old')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('security-remove-confirm')));
      await tester.pumpAndSettle();
      expect((await devices(pAsha).doc('old').get()).exists, isFalse);
      expect((await devices(pAsha).doc(id).get()).exists, isTrue);
      expect(find.text('Pixel 7'), findsNothing);
    });

    testWidgets('adds a recovery email when none is linked', (tester) async {
      await rig.seedCouple();
      await seedDevice(await myDeviceId());
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('security-add-email')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('recovery-email-field')),
        'asha@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('recovery-password-field')),
        '123',
      );
      await tester.tap(find.byKey(const Key('recovery-email-add')));
      await tester.pumpAndSettle();
      expect(find.text('Use at least 6 characters.'), findsOneWidget);
      expect(rig.reauth.added, isEmpty);

      await tester.enterText(
        find.byKey(const Key('recovery-password-field')),
        'secret1',
      );
      await tester.tap(find.byKey(const Key('recovery-email-add')));
      await tester.pumpAndSettle();
      expect(rig.reauth.added, ['asha@example.com']);
      expect(find.byKey(const Key('security-add-email')), findsNothing);
      expect(find.text('asha@example.com'), findsOneWidget);
    });

    testWidgets('shows recent notices', (tester) async {
      await rig.seedCouple();
      await seedDevice(await myDeviceId());
      await events(pAsha).doc('e1').set({
        'type': 'newPhoneRejected',
        'deviceName': 'Galaxy A15',
        'at': Timestamp.fromDate(rig.now),
      });
      await pumpScreen(tester);
      expect(
        find.text('Sign-in on Galaxy A15 stopped by your partner'),
        findsOneWidget,
      );
    });
  });

  test('event ids say which phone they are about', () {
    const e = SecurityEvent(
      id: 'wait_abc',
      type: SecurityEventType.newPhoneWaiting,
      deviceName: 'X',
    );
    expect(e.isAbout('abc'), isTrue);
    expect(e.isAbout('ab'), isFalse);
    expect(
      SecurityEvent.approvedId(
        'abc',
        DateTime(2026),
      ).startsWith('approved_abc_'),
      isTrue,
    );
  });
}
