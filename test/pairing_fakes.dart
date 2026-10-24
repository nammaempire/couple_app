// Fakes for mobile-number sign-in, pairing by number, ending a pairing and
// sign-in protection, shared by their tests (and the screenshot suite): an
// in-memory backend, a hand-moved clock, and fake SMS, server, biometric,
// share sheet, phone identity and account re-checks.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:couple_app/core/backend/backend.dart';
import 'package:couple_app/core/backend/memory_backend.dart';
import 'package:couple_app/core/providers/core_providers.dart';
import 'package:couple_app/core/services/screen_privacy.dart';
import 'package:couple_app/core/services/storage_service.dart';
import 'package:couple_app/features/app_lock/data/biometric_auth.dart';
import 'package:couple_app/features/app_lock/providers/app_lock_providers.dart';
import 'package:couple_app/features/auth/data/auth_service.dart';
import 'package:couple_app/features/auth/data/phone_auth_gateway.dart';
import 'package:couple_app/features/auth/data/phone_number_service.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/calls/data/call_service.dart';
import 'package:couple_app/features/calls/providers/call_providers.dart';
import 'package:couple_app/features/couple/data/couple_service.dart';
import 'package:couple_app/features/couple/data/end_pairing_gateway.dart';
import 'package:couple_app/features/couple/data/pair_request_service.dart';
import 'package:couple_app/features/couple/data/separation_service.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/couple/providers/pair_request_providers.dart';
import 'package:couple_app/features/couple/providers/separation_providers.dart';
import 'package:couple_app/features/onboarding/widgets/invite_share.dart';
import 'package:couple_app/features/security/data/account_reauth.dart';
import 'package:couple_app/features/security/data/device_identity_service.dart';
import 'package:couple_app/features/security/data/device_trust_service.dart';
import 'package:couple_app/features/security/providers/security_providers.dart';
import 'package:couple_app/features/vault/data/device_keystore.dart';
import 'package:couple_app/features/vault/data/device_name.dart';
import 'package:couple_app/features/vault/data/vault_crypto.dart';

const pAsha = 'asha';
const pRavi = 'ravi';
const pCouple = 'c1';
const ashaPhone = '+919876543210';
const raviPhone = '+919812343210';

/// Sends codes and checks them, as Firebase would, without a network.
class FakePhoneAuthGateway implements PhoneAuthGateway {
  /// The code the "SMS" carries.
  String code = '123456';

  /// Thrown by the next [sendCode], once.
  PhoneAuthException? sendError;

  /// Pretend Android read the SMS before the code was even sent.
  bool instantVerify = false;

  final sent = <({String phone, PhoneAuthMode mode, bool resend})>[];
  final confirmed = <({String phone, String code, PhoneAuthMode mode})>[];
  void Function(String?)? _autoVerified;
  int _verifications = 0;

  @override
  Future<PhoneCodeTicket> sendCode(
    String phoneNumber, {
    required PhoneAuthMode mode,
    PhoneCodeTicket? resend,
    void Function(String? smsCode)? onAutoVerified,
  }) async {
    sent.add((phone: phoneNumber, mode: mode, resend: resend != null));
    final error = sendError;
    if (error != null) {
      sendError = null;
      throw error;
    }
    _autoVerified = onAutoVerified;
    return PhoneCodeTicket(
      phoneNumber: phoneNumber,
      verificationId: 'v${_verifications++}',
      resendToken: 7,
      autoVerified: instantVerify,
    );
  }

  /// Android read the SMS after the code went out.
  void autoRetrieve() => _autoVerified?.call(code);

  @override
  Future<void> confirmCode(
    PhoneCodeTicket ticket,
    String smsCode, {
    required PhoneAuthMode mode,
  }) async {
    if (smsCode != code) {
      throw PhoneAuthException(PhoneAuthError.wrongCode);
    }
    confirmed.add((phone: ticket.phoneNumber, code: smsCode, mode: mode));
  }
}

/// [AuthService] with only what the phone screens use.
class FakePhoneAuthService implements AuthService {
  FakePhoneAuthService(this.uidValue);

  final String uidValue;
  int ensureProfileCalls = 0;
  int signOutCalls = 0;

  @override
  String? get uid => uidValue;

  @override
  Future<String?> ensureProfile() async {
    ensureProfileCalls++;
    return uidValue;
  }

  @override
  Future<void> signOut() async => signOutCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The two callables, answered by hand.
class FakeEndPairingGateway implements EndPairingGateway {
  /// Thrown by every call while set.
  EndPairingException? error;
  EndPairingStatus status = EndPairingStatus.ended;

  final finalized = <String>[];
  final leftNow = <String>[];

  /// Runs on a successful call, e.g. to play the server's writes.
  Future<void> Function(String coupleId, String how)? onEnd;

  @override
  Future<EndPairingResult> finalizeSeparation(String coupleId) async {
    finalized.add(coupleId);
    final e = error;
    if (e != null) throw e;
    await onEnd?.call(coupleId, 'oneSided');
    return EndPairingResult(status, 'oneSided');
  }

  @override
  Future<EndPairingResult> leaveNow(String coupleId) async {
    leftNow.add(coupleId);
    final e = error;
    if (e != null) throw e;
    await onEnd?.call(coupleId, 'leftNow');
    return EndPairingResult(status, 'leftNow');
  }
}

/// Answers the phone-lock prompt with [result].
class FakeLockBiometrics implements BiometricAuth {
  FakeLockBiometrics({this.available = true, this.result = true});

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

/// Uploads nothing; the pairing screens only need it to exist.
class FakeStorageService implements StorageService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeScreenSecurity implements ScreenSecurity {
  final calls = <bool>[];
  bool get secure => calls.isNotEmpty && calls.last;

  @override
  Future<void> setSecure(bool secure) async => calls.add(secure);
}

class FakeScreenshotDetector implements ScreenshotDetector {
  @override
  Stream<void> get screenshots => const Stream.empty();
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}

/// A signed-in Firebase user with only a uid.
class FakeUser implements User {
  FakeUser(this.uidValue);

  final String uidValue;

  @override
  String get uid => uidValue;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Names the phone.
class FakePhoneName implements DeviceNameSource {
  FakePhoneName(this.name);

  String name;

  @override
  Future<String> deviceName() async => name;
}

/// The account's password and Google re-checks, answered by hand.
class FakeAccountReauth implements AccountReauth {
  ReauthOptions current = ReauthOptions.none;

  /// The password [withPassword] accepts.
  String password = 'secret';

  /// What [withGoogle] does: true (it's them), false (picker closed), or
  /// throws [googleError] when set.
  bool googleResult = true;
  ReauthError? googleError;

  final passwords = <String>[];
  int googleCalls = 0;
  int resets = 0;
  final added = <String>[];

  @override
  ReauthOptions options() => current;

  @override
  Future<void> withPassword(String password) async {
    passwords.add(password);
    if (password != this.password) {
      throw ReauthException(ReauthError.wrongPassword);
    }
  }

  @override
  Future<bool> withGoogle() async {
    googleCalls++;
    final error = googleError;
    if (error != null) throw ReauthException(error);
    return googleResult;
  }

  @override
  Future<void> sendPasswordReset() async => resets++;

  @override
  Future<void> addRecoveryEmail({
    required String email,
    required String password,
  }) async {
    added.add(email);
    current = ReauthOptions(
      passwordEmail: email,
      googleEmail: current.googleEmail,
    );
  }
}

/// An in-memory backend for the pairing features, with Asha and Ravi.
class PairingRig {
  PairingRig({MemoryBackend? backend}) : backend = backend ?? MemoryBackend();

  /// The documents behind [db], for seeding and assertions.
  final MemoryBackend backend;
  late final Db db = Db(backend);
  DateTime now = DateTime(2026, 10, 21, 10);
  final phoneGateway = FakePhoneAuthGateway();
  final endGateway = FakeEndPairingGateway();
  final biometrics = FakeLockBiometrics();
  final security = FakeScreenSecurity();
  final shared = <String>[];

  /// This phone's secure storage (its device id lives here).
  final keystore = MemoryDeviceKeystore();
  final phoneName = FakePhoneName('Pixel 9');
  final reauth = FakeAccountReauth();
  late final identity = DeviceIdentityService(
    keystore: keystore,
    crypto: VaultCrypto.forTests(seed: 7),
    names: phoneName,
  );
  DeviceTrustService get trust => DeviceTrustService(db: db);

  DateTime clock() => now;

  CoupleService get couples => CoupleService(db: db);
  PhoneNumberService get phones => PhoneNumberService(db: db);
  SeparationService get separations => SeparationService(db: db, clock: clock);
  PairRequestService get requests =>
      PairRequestService(db: db, couples: couples, phones: phones);

  DocumentReference<Map<String, dynamic>> get couple =>
      db.collection('couples').doc(pCouple);

  /// Asha and Ravi, paired, with numbers.
  Future<void> seedCouple({
    Map<String, dynamic>? separation,
    Map<String, dynamic> ashaExtra = const {},
    Map<String, dynamic> raviExtra = const {},
  }) async {
    await db.collection('users').doc(pAsha).set({
      'displayName': 'Asha',
      'coupleId': pCouple,
      'profileComplete': true,
      'setupComplete': true,
      'phone': ashaPhone,
      ...ashaExtra,
    });
    await db.collection('users').doc(pRavi).set({
      'displayName': 'Ravi',
      'coupleId': pCouple,
      'profileComplete': true,
      'setupComplete': true,
      'phone': raviPhone,
      ...raviExtra,
    });
    await couple.set({
      'inviteCode': 'K7MP3Q',
      'memberIds': [pAsha, pRavi],
      'coupleName': 'Asha & Ravi',
      'separation': ?separation,
    });
  }

  /// A separation as the app writes it, asked by [by] at [now].
  Map<String, dynamic> separationMap({
    String by = pAsha,
    String status = 'requested',
    Duration left = const Duration(days: 14),
  }) => {
    'requestedBy': by,
    'requestedAt': Timestamp.fromDate(now),
    'status': status,
    'agreedAt': status == 'agreed' ? Timestamp.fromDate(now) : null,
    'declinedAt': status == 'declined' ? Timestamp.fromDate(now) : null,
    'effectiveAt': Timestamp.fromDate(now.add(left)),
  };

  /// Everything a screen for [uid] needs, backed by [db].
  List<Override> overrides(String uid, {AuthService? auth}) => [
    profileProvider.overrideWith(
      (ref, id) => db
          .collection('users')
          .doc(id)
          .snapshots()
          .map((d) => d.exists ? AppUser.fromDoc(d) : null),
    ),
    currentUserProvider.overrideWithBuild((ref, notifier) {
      final profile = ref.watch(profileProvider(uid)).value;
      if (profile != null) return profile;
      final previous = notifier.stateOrNull;
      if (previous != null) return previous;
      throw StateError('No profile yet');
    }),
    authServiceProvider.overrideWithValue(auth ?? FakePhoneAuthService(uid)),
    coupleServiceProvider.overrideWithValue(couples),
    phoneNumberServiceProvider.overrideWithValue(phones),
    phoneAuthGatewayProvider.overrideWithValue(phoneGateway),
    pairRequestServiceProvider.overrideWithValue(requests),
    separationClockProvider.overrideWithValue(clock),
    separationServiceProvider.overrideWithValue(separations),
    endPairingGatewayProvider.overrideWithValue(endGateway),
    biometricAuthProvider.overrideWithValue(biometrics),
    inviteSharerProvider.overrideWithValue((text) async => shared.add(text)),
    callServiceProvider.overrideWithValue(CallService(db: db)),
    storageServiceProvider.overrideWithValue(FakeStorageService()),
    screenSecurityProvider.overrideWithValue(security),
    screenshotDetectorProvider.overrideWithValue(FakeScreenshotDetector()),
    ...securityOverrides(),
  ];

  /// Sign-in protection on [db], this rig's phone and clock.
  List<Override> securityOverrides() => [
    deviceIdentityServiceProvider.overrideWithValue(identity),
    deviceTrustServiceProvider.overrideWithValue(trust),
    accountReauthProvider.overrideWithValue(reauth),
    securityClockProvider.overrideWithValue(clock),
  ];
}

/// Shows [child] once [uid]'s profile (and, with [needsCouple], the
/// couple) has loaded, like the auth gate.
class PairingReady extends ConsumerWidget {
  const PairingReady({
    super.key,
    required this.uid,
    required this.child,
    this.needsCouple = true,
  });

  final String uid;
  final Widget child;
  final bool needsCouple;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider(uid)).value;
    if (profile == null) return const SizedBox.shrink();
    if (needsCouple &&
        (profile.coupleId == null || ref.watch(coupleProvider).value == null)) {
      return const SizedBox.shrink();
    }
    return child;
  }
}
