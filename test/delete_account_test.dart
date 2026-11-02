import 'package:couple_app/features/account/data/account_deletion.dart';
import 'package:couple_app/features/account/screens/delete_account_screen.dart';
import 'package:couple_app/features/auth/data/phone_auth_gateway.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/security/data/account_reauth.dart';
import 'package:couple_app/features/security/providers/security_providers.dart';
import 'package:couple_app/features/vault/data/device_keystore.dart';
import 'package:couple_app/features/vault/providers/vault_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pairing_fakes.dart';

class FakeDeletionGateway implements AccountDeletionGateway {
  final failures = <AccountDeletionFailure>[];
  bool signInDeletedByServer = true;
  int serverCalls = 0;
  int hereCalls = 0;

  @override
  Future<bool> deleteOnServer() async {
    serverCalls++;
    if (failures.isNotEmpty) {
      throw AccountDeletionException(failures.removeAt(0));
    }
    return signInDeletedByServer;
  }

  @override
  Future<void> deleteSignInHere() async => hereCalls++;
}

class FakeSmsGateway implements PhoneAuthGateway {
  final sent = <PhoneAuthMode>[];
  final confirmed = <String>[];

  @override
  Future<PhoneCodeTicket> sendCode(
    String phoneNumber, {
    required PhoneAuthMode mode,
    PhoneCodeTicket? resend,
    void Function(String? smsCode)? onAutoVerified,
  }) async {
    sent.add(mode);
    return PhoneCodeTicket(phoneNumber: phoneNumber, verificationId: 'v1');
  }

  @override
  Future<void> confirmCode(
    PhoneCodeTicket ticket,
    String smsCode, {
    required PhoneAuthMode mode,
  }) async {
    if (smsCode != '123456') {
      throw PhoneAuthException(PhoneAuthError.wrongCode);
    }
    confirmed.add('$smsCode/${mode.name}');
  }
}

void main() {
  late FakeDeletionGateway gateway;
  late FakeAccountReauth reauth;
  late FakeSmsGateway sms;
  late FakePhoneAuthService auth;
  late MemoryDeviceKeystore keystore;

  setUp(() {
    gateway = FakeDeletionGateway();
    reauth = FakeAccountReauth();
    sms = FakeSmsGateway();
    auth = FakePhoneAuthService('ann');
    keystore = MemoryDeviceKeystore();
  });

  Future<void> open(WidgetTester tester, {String? phone}) async {
    final me = AppUser(
      uid: 'ann',
      displayName: 'Ann',
      coupleId: 'c1',
      phone: phone,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithBuild((ref, notifier) => me),
          coupleProvider.overrideWith(
            (ref) => Stream.value(
              const Couple(
                id: 'c1',
                inviteCode: 'ABC234',
                memberIds: ['ann', 'bob'],
              ),
            ),
          ),
          partnerNameProvider.overrideWithValue('Bob'),
          accountDeletionGatewayProvider.overrideWithValue(gateway),
          accountReauthProvider.overrideWithValue(reauth),
          phoneAuthGatewayProvider.overrideWithValue(sms),
          authServiceProvider.overrideWithValue(auth),
          deviceKeystoreProvider.overrideWithValue(keystore),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    Navigator.of(context).push(DeleteAccountScreen.route()),
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

  Future<void> typeDelete(WidgetTester tester) async {
    final next = find.byKey(const Key('delete-account-continue'));
    expect(tester.widget<FilledButton>(next).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('delete-account-type')),
      'delete',
    );
    await tester.pump();
    await tester.tap(next);
    await tester.pumpAndSettle();
  }

  testWidgets('explains, asks for DELETE and the password, then deletes', (
    tester,
  ) async {
    reauth.current = const ReauthOptions(passwordEmail: 'ann@example.com');
    await open(tester);
    expect(
      find.textContaining('Bob will see that the pairing ended'),
      findsOneWidget,
    );
    await typeDelete(tester);

    await tester.enterText(
      find.byKey(const Key('delete-account-password')),
      'wrong',
    );
    await tester.tap(find.byKey(const Key('delete-account-with-password')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('delete-account-error')), findsOneWidget);
    expect(gateway.serverCalls, 0);

    await tester.enterText(
      find.byKey(const Key('delete-account-password')),
      'secret',
    );
    await tester.tap(find.byKey(const Key('delete-account-with-password')));
    await tester.pumpAndSettle();
    expect(gateway.serverCalls, 1);
    expect(gateway.hereCalls, 0, reason: 'the server deleted the sign-in');
    expect(auth.signOutCalls, 1);
    expect(find.byType(DeleteAccountScreen), findsNothing);
    expect(find.text('Your account has been deleted.'), findsOneWidget);
  });

  testWidgets('a phone-only account confirms with an SMS code', (tester) async {
    gateway.signInDeletedByServer = false;
    await open(tester, phone: '+919000000001');
    await typeDelete(tester);
    await tester.tap(find.byKey(const Key('delete-account-send-code')));
    await tester.pumpAndSettle();
    expect(sms.sent, [PhoneAuthMode.reauth]);
    await tester.enterText(
      find.byKey(const Key('delete-account-code')),
      '123456',
    );
    await tester.tap(find.byKey(const Key('delete-account-with-code')));
    await tester.pumpAndSettle();
    expect(sms.confirmed, ['123456/reauth']);
    expect(gateway.serverCalls, 1);
    expect(gateway.hereCalls, 1, reason: 'the phone deletes the sign-in');
    expect(auth.signOutCalls, 1);
  });

  testWidgets('a server refusal keeps the account and says why', (
    tester,
  ) async {
    reauth.current = const ReauthOptions(googleEmail: 'ann@gmail.com');
    gateway.failures.add(AccountDeletionFailure.busy);
    await open(tester);
    await typeDelete(tester);
    await tester.tap(find.byKey(const Key('delete-account-with-google')));
    await tester.pumpAndSettle();
    expect(reauth.googleCalls, 1);
    expect(find.text(AccountDeletionFailure.busy.message), findsOneWidget);
    expect(auth.signOutCalls, 0);
    expect(find.byType(DeleteAccountScreen), findsOneWidget);

    // Trying again works.
    await tester.tap(find.byKey(const Key('delete-account-with-google')));
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 1);
  });

  test('server error codes map to messages', () {
    expect(
      FunctionsAccountDeletionGateway.failureFor('failed-precondition'),
      AccountDeletionFailure.needsRecentSignIn,
    );
    expect(
      FunctionsAccountDeletionGateway.failureFor('aborted'),
      AccountDeletionFailure.busy,
    );
  });
}
