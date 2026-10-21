import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/core/theme/app_theme.dart';
import 'package:couple_app/features/auth/data/phone_auth_gateway.dart';
import 'package:couple_app/features/auth/models/phone_number.dart';
import 'package:couple_app/features/onboarding/screens/phone_sign_in_screen.dart';

import 'pairing_fakes.dart';

void main() {
  group('PhoneNumbers', () {
    final india = PhoneCountry.india;

    test('India: ten digits starting 6–9, spaces and a trunk 0 allowed', () {
      expect(PhoneNumbers.toE164(india, '98765 43210'), '+919876543210');
      expect(PhoneNumbers.toE164(india, '098765-43210'), '+919876543210');
      expect(PhoneNumbers.validate(india, ''), 'Enter your mobile number.');
      expect(PhoneNumbers.validate(india, '98765'), contains('10 digits'));
      expect(PhoneNumbers.validate(india, '1234567890'), contains('India'));
      expect(PhoneNumbers.toE164(india, '987654321012'), isNull);
    });

    test('other countries use their own lengths', () {
      final uk = PhoneCountry.all.firstWhere((c) => c.iso == 'GB');
      expect(PhoneNumbers.toE164(uk, '7700 900123'), '+447700900123');
      expect(PhoneNumbers.toE164(uk, '770090'), isNull);
    });

    test('masks and formats', () {
      expect(PhoneNumbers.mask('+919876543210'), '+91 98•••• 3210');
      expect(PhoneNumbers.format('+919876543210'), '+91 98765 43210');
      expect(PhoneNumbers.isE164('+919876543210'), isTrue);
      expect(PhoneNumbers.isE164('919876543210'), isFalse);
    });

    test('Firebase error codes map to the four cases on screen', () {
      expect(
        PhoneAuthError.fromCode('invalid-phone-number'),
        PhoneAuthError.invalidNumber,
      );
      expect(
        PhoneAuthError.fromCode('invalid-verification-code'),
        PhoneAuthError.wrongCode,
      );
      expect(
        PhoneAuthError.fromCode('too-many-requests'),
        PhoneAuthError.tooManyAttempts,
      );
      expect(
        PhoneAuthError.fromCode('quota-exceeded'),
        PhoneAuthError.quotaExceeded,
      );
      expect(
        PhoneAuthError.fromCode('billing-not-enabled'),
        PhoneAuthError.unavailable,
      );
    });
  });

  group('PhoneNumberService', () {
    test('saves the number on the profile and claims phoneIndex', () async {
      final rig = PairingRig();
      await rig.db.collection('users').doc(pAsha).set({'displayName': 'A'});
      await rig.phones.saveVerifiedPhone(uid: pAsha, e164: ashaPhone);

      final user = await rig.db.collection('users').doc(pAsha).get();
      expect(user.data()!['phone'], ashaPhone);
      expect(user.data()!['displayName'], 'A');
      final index = await rig.db.collection('phoneIndex').doc(ashaPhone).get();
      expect(index.data()!['uid'], pAsha);
      expect(index.data()!.keys.toSet(), {'uid', 'createdAt'});
      expect(await rig.phones.lookup(ashaPhone), pAsha);
      expect(await rig.phones.lookup(raviPhone), isNull);
    });

    test('refuses anything that is not E.164', () {
      final rig = PairingRig();
      expect(
        () => rig.phones.saveVerifiedPhone(uid: pAsha, e164: '98765'),
        throwsArgumentError,
      );
    });
  });

  group('PhoneSignInScreen', () {
    late PairingRig rig;
    late FakePhoneAuthService auth;

    setUp(() {
      rig = PairingRig();
      auth = FakePhoneAuthService(pAsha);
    });

    Future<void> pump(
      WidgetTester tester, {
      PhoneAuthMode mode = PhoneAuthMode.signIn,
    }) async {
      await rig.db.collection('users').doc(pAsha).set({'displayName': 'Asha'});
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: rig.overrides(pAsha, auth: auth),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<bool>(
                      builder: (_) => PhoneSignInScreen(mode: mode),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> enterNumber(WidgetTester tester, String number) async {
      await tester.enterText(
        find.byKey(const Key('phone-number-field')),
        number,
      );
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
    }

    testWidgets('validates the number before sending anything', (tester) async {
      await pump(tester);
      expect(find.text('🇮🇳'), findsOneWidget);
      expect(find.text('+91'), findsOneWidget);

      await enterNumber(tester, '12345');
      expect(find.textContaining('10 digits'), findsOneWidget);
      await enterNumber(tester, '1234567890');
      expect(
        find.text('That doesn\'t look like a India mobile number.'),
        findsOneWidget,
      );
      expect(rig.phoneGateway.sent, isEmpty);
    });

    testWidgets('picks another country', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('phone-country-button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Search'), 'king');
      await tester.pumpAndSettle();
      await tester.tap(find.text('United Kingdom'));
      await tester.pumpAndSettle();
      expect(find.text('+44'), findsOneWidget);
      await enterNumber(tester, '7700 900123');
      expect(rig.phoneGateway.sent.single.phone, '+447700900123');
    });

    testWidgets('sends a code, signs in with it and saves the number', (
      tester,
    ) async {
      await pump(tester);
      await enterNumber(tester, '98765 43210');
      expect(rig.phoneGateway.sent.single.phone, ashaPhone);
      expect(rig.phoneGateway.sent.single.mode, PhoneAuthMode.signIn);
      expect(find.text('Enter the code'), findsOneWidget);
      expect(find.textContaining('+91 98765 43210'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('otp-field')), '123456');
      await tester.pumpAndSettle();

      expect(rig.phoneGateway.confirmed.single.code, '123456');
      expect(auth.ensureProfileCalls, 1);
      final user = await rig.db.collection('users').doc(pAsha).get();
      expect(user.data()!['phone'], ashaPhone);
      final index = await rig.db.collection('phoneIndex').doc(ashaPhone).get();
      expect(index.data()!['uid'], pAsha);
      await tester.pump(const Duration(seconds: 31));
    });

    testWidgets('a wrong code says so and clears the boxes', (tester) async {
      await pump(tester);
      await enterNumber(tester, '9876543210');
      await tester.enterText(find.byKey(const Key('otp-field')), '000000');
      await tester.pumpAndSettle();
      expect(find.text(PhoneAuthError.wrongCode.message), findsOneWidget);
      expect(rig.phoneGateway.confirmed, isEmpty);
      final field = tester.widget<TextField>(
        find.byKey(const Key('otp-field')),
      );
      expect(field.controller!.text, isEmpty);
      await tester.pump(const Duration(seconds: 31));
    });

    testWidgets('resend waits 30 seconds', (tester) async {
      await pump(tester);
      await enterNumber(tester, '9876543210');
      expect(find.text('Resend code in 30s'), findsOneWidget);
      final resend = find.widgetWithText(TextButton, 'Resend code in 30s');
      expect(tester.widget<TextButton>(resend).onPressed, isNull);

      await tester.pump(const Duration(seconds: 10));
      expect(find.text('Resend code in 20s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 20));
      await tester.pump();
      expect(find.text('Resend code'), findsOneWidget);

      await tester.tap(find.text('Resend code'));
      await tester.pumpAndSettle();
      expect(rig.phoneGateway.sent, hasLength(2));
      expect(rig.phoneGateway.sent.last.resend, isTrue);
      expect(find.text('Resend code in 30s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 31));
    });

    testWidgets('shows send errors: too many attempts and quota', (
      tester,
    ) async {
      await pump(tester);
      rig.phoneGateway.sendError = PhoneAuthException(
        PhoneAuthError.tooManyAttempts,
      );
      await enterNumber(tester, '9876543210');
      expect(find.text(PhoneAuthError.tooManyAttempts.message), findsOneWidget);
      expect(find.text('Send code'), findsOneWidget);

      rig.phoneGateway.sendError = PhoneAuthException(
        PhoneAuthError.quotaExceeded,
      );
      await enterNumber(tester, '9876543210');
      expect(find.text(PhoneAuthError.quotaExceeded.message), findsOneWidget);

      rig.phoneGateway.sendError = PhoneAuthException(
        PhoneAuthError.invalidNumber,
      );
      await enterNumber(tester, '9876543210');
      expect(find.text(PhoneAuthError.invalidNumber.message), findsOneWidget);
    });

    testWidgets('Android reading the SMS finishes by itself', (tester) async {
      await pump(tester);
      await enterNumber(tester, '9876543210');
      rig.phoneGateway.autoRetrieve();
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(const Key('otp-field')),
      );
      expect(field.controller!.text, '123456');
      final index = await rig.db.collection('phoneIndex').doc(ashaPhone).get();
      expect(index.exists, isTrue);
      await tester.pump(const Duration(seconds: 31));
    });

    testWidgets('adds a number to an existing account and pops', (
      tester,
    ) async {
      await pump(tester, mode: PhoneAuthMode.link);
      expect(find.text('Add your mobile number'), findsOneWidget);
      await enterNumber(tester, '98765 43210');
      expect(rig.phoneGateway.sent.single.mode, PhoneAuthMode.link);
      await tester.enterText(find.byKey(const Key('otp-field')), '123456');
      await tester.pumpAndSettle();

      expect(rig.phoneGateway.confirmed.single.mode, PhoneAuthMode.link);
      // Linking keeps the profile; no new one is made.
      expect(auth.ensureProfileCalls, 0);
      final user = await rig.db.collection('users').doc(pAsha).get();
      expect(user.data()!['phone'], ashaPhone);
      expect(user.data()!['displayName'], 'Asha');
      expect(
        (await rig.db.collection('phoneIndex').doc(ashaPhone).get())
            .data()!['uid'],
        pAsha,
      );
      expect(find.text('open'), findsOneWidget);
    });
  });
}
