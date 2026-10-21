import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

/// Whether a verified number signs in, or is added to the signed-in account.
enum PhoneAuthMode { signIn, link }

/// What went wrong with a mobile-number sign-in, in words the screens can
/// explain.
enum PhoneAuthError {
  invalidNumber,
  wrongCode,
  codeExpired,
  tooManyAttempts,
  quotaExceeded,

  /// The number already belongs to another account (adding a number).
  numberInUse,

  /// Phone sign-in isn't switched on for the project yet (or this build
  /// isn't registered with it).
  unavailable,
  network,
  other;

  /// A sentence for the screen.
  String get message => switch (this) {
    invalidNumber => 'That number doesn\'t look right. Check it and try again.',
    wrongCode => 'That code isn\'t right. Check the SMS and try again.',
    codeExpired => 'That code has expired. Send a new one.',
    tooManyAttempts =>
      'Too many attempts from this phone. Wait a while, then try again.',
    quotaExceeded =>
      'We can\'t send more codes right now. Try again later, or use Google '
          'or email.',
    numberInUse => 'That number is already used by another account.',
    unavailable =>
      'Sign-in with a mobile number isn\'t available yet. Use Google or '
          'email for now.',
    network => 'No connection. Check your network and try again.',
    other => 'Something went wrong. Please try again.',
  };

  static PhoneAuthError fromCode(String code) => switch (code) {
    'invalid-phone-number' || 'missing-phone-number' => invalidNumber,
    'invalid-verification-code' || 'missing-verification-code' => wrongCode,
    'session-expired' || 'code-expired' => codeExpired,
    'too-many-requests' => tooManyAttempts,
    'quota-exceeded' => quotaExceeded,
    'credential-already-in-use' ||
    'account-exists-with-different-credential' => numberInUse,
    'operation-not-allowed' ||
    'billing-not-enabled' ||
    'app-not-authorized' ||
    'invalid-app-credential' ||
    'missing-client-identifier' => unavailable,
    'network-request-failed' => network,
    _ => other,
  };
}

class PhoneAuthException implements Exception {
  PhoneAuthException(this.error, [this.detail]);

  final PhoneAuthError error;
  final String? detail;

  String get message => error.message;

  @override
  String toString() => 'PhoneAuthException(${error.name}: $detail)';
}

/// A code sent to [phoneNumber], to confirm or resend.
class PhoneCodeTicket {
  const PhoneCodeTicket({
    required this.phoneNumber,
    required this.verificationId,
    this.resendToken,
    this.autoVerified = false,
  });

  /// E.164, e.g. `+919876543210`.
  final String phoneNumber;
  final String verificationId;

  /// Lets a resend skip the extra app check.
  final int? resendToken;

  /// Android read the SMS (or verified the number) by itself, and the
  /// sign-in is already done; there is no code to type.
  final bool autoVerified;
}

/// Sends the SMS code and signs in (or adds the number) with it.
///
/// Behind an interface so tests can fake it.
abstract class PhoneAuthGateway {
  /// Sends a code to [phoneNumber] (E.164). Pass the previous [resend]
  /// ticket to send another.
  ///
  /// On Android the phone may read the SMS itself. If that happens before
  /// the code is sent, the returned ticket is [PhoneCodeTicket.autoVerified];
  /// if it happens afterwards, [onAutoVerified] runs with the code (when the
  /// system shared it) once the sign-in is done.
  Future<PhoneCodeTicket> sendCode(
    String phoneNumber, {
    required PhoneAuthMode mode,
    PhoneCodeTicket? resend,
    void Function(String? smsCode)? onAutoVerified,
  });

  /// Signs in, or adds the number to the signed-in account, with the
  /// six-digit [smsCode].
  Future<void> confirmCode(
    PhoneCodeTicket ticket,
    String smsCode, {
    required PhoneAuthMode mode,
  });
}

/// [PhoneAuthGateway] through `FirebaseAuth.verifyPhoneNumber`.
///
/// Android verifies the app with Play Integrity (falling back to a
/// reCAPTCHA page) and reads the SMS with the SMS Retriever API, both inside
/// the Firebase SDK, so nothing else is needed on the app side.
class FirebasePhoneAuthGateway implements PhoneAuthGateway {
  FirebasePhoneAuthGateway({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  /// How long Android waits to read the SMS by itself.
  static const autoRetrievalTimeout = Duration(seconds: 30);

  @override
  Future<PhoneCodeTicket> sendCode(
    String phoneNumber, {
    required PhoneAuthMode mode,
    PhoneCodeTicket? resend,
    void Function(String? smsCode)? onAutoVerified,
  }) {
    final ticket = Completer<PhoneCodeTicket>();
    var autoHandled = false;

    Future<void> autoVerify(PhoneAuthCredential credential) async {
      if (autoHandled) return;
      autoHandled = true;
      try {
        await _use(credential, mode);
      } on PhoneAuthException catch (e) {
        if (!ticket.isCompleted) ticket.completeError(e);
        return;
      }
      if (!ticket.isCompleted) {
        ticket.complete(
          PhoneCodeTicket(
            phoneNumber: phoneNumber,
            verificationId: credential.verificationId ?? '',
            autoVerified: true,
          ),
        );
      } else {
        onAutoVerified?.call(credential.smsCode);
      }
    }

    _auth
        .verifyPhoneNumber(
          phoneNumber: phoneNumber,
          timeout: autoRetrievalTimeout,
          forceResendingToken: resend?.resendToken,
          verificationCompleted: autoVerify,
          verificationFailed: (e) {
            // After the code went out this only means the automatic read
            // failed; the user can still type the code.
            if (!ticket.isCompleted) ticket.completeError(_wrap(e));
          },
          codeSent: (verificationId, resendToken) {
            if (ticket.isCompleted) return;
            ticket.complete(
              PhoneCodeTicket(
                phoneNumber: phoneNumber,
                verificationId: verificationId,
                resendToken: resendToken,
              ),
            );
          },
          codeAutoRetrievalTimeout: (_) {},
        )
        .catchError((Object e) {
          if (!ticket.isCompleted) ticket.completeError(_wrap(e));
        });
    return ticket.future;
  }

  @override
  Future<void> confirmCode(
    PhoneCodeTicket ticket,
    String smsCode, {
    required PhoneAuthMode mode,
  }) {
    return _use(
      PhoneAuthProvider.credential(
        verificationId: ticket.verificationId,
        smsCode: smsCode,
      ),
      mode,
    );
  }

  Future<void> _use(PhoneAuthCredential credential, PhoneAuthMode mode) async {
    try {
      switch (mode) {
        case PhoneAuthMode.signIn:
          await _auth.signInWithCredential(credential);
        case PhoneAuthMode.link:
          final user = _auth.currentUser;
          if (user == null) throw PhoneAuthException(PhoneAuthError.other);
          try {
            await user.linkWithCredential(credential);
          } on FirebaseAuthException catch (e) {
            // Already has a number: replace it with this one.
            if (e.code != 'provider-already-linked') rethrow;
            await user.updatePhoneNumber(credential);
          }
          // The security rules read the number from the ID token, so get
          // a fresh one that carries it before anything is written.
          await user.getIdToken(true);
      }
    } on PhoneAuthException {
      rethrow;
    } catch (e) {
      throw _wrap(e);
    }
  }

  static PhoneAuthException _wrap(Object e) {
    if (e is PhoneAuthException) return e;
    if (e is FirebaseAuthException) {
      return PhoneAuthException(PhoneAuthError.fromCode(e.code), e.message);
    }
    return PhoneAuthException(PhoneAuthError.other, '$e');
  }
}
