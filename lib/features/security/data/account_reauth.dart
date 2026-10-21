import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// The ways the signed-in account can prove it's its owner, besides SMS.
@immutable
class ReauthOptions {
  const ReauthOptions({this.passwordEmail, this.googleEmail});

  /// The email of a linked email/password sign-in (or recovery email).
  final String? passwordEmail;

  /// The email of a linked Google account.
  final String? googleEmail;

  static const none = ReauthOptions();

  bool get password => passwordEmail != null;
  bool get google => googleEmail != null;
  bool get any => password || google;

  /// The email to show as the account's recovery email.
  String? get email => passwordEmail ?? googleEmail;
}

/// What went wrong confirming the account, in words for the screen.
enum ReauthError {
  wrongPassword,
  wrongAccount,
  tooManyAttempts,
  emailInUse,
  invalidEmail,
  weakPassword,
  needsRecentSignIn,
  network,
  other;

  String get message => switch (this) {
    wrongPassword => 'That password isn\'t right. Try again.',
    wrongAccount =>
      'That\'s a different Google account. Pick the one you use here.',
    tooManyAttempts => 'Too many tries. Wait a little, then try again.',
    emailInUse => 'That email is already used by another account.',
    invalidEmail => 'That email doesn\'t look right.',
    weakPassword => 'Use at least 6 characters for the password.',
    needsRecentSignIn =>
      'For safety, sign out and back in, then add your email.',
    network => 'No connection. Check your network and try again.',
    other => 'Something went wrong. Please try again.',
  };

  static ReauthError fromCode(String code) => switch (code) {
    'wrong-password' ||
    'invalid-credential' ||
    'invalid-login-credentials' => wrongPassword,
    'user-mismatch' => wrongAccount,
    'too-many-requests' => tooManyAttempts,
    'email-already-in-use' ||
    'credential-already-in-use' ||
    'provider-already-linked' => emailInUse,
    'invalid-email' => invalidEmail,
    'weak-password' => weakPassword,
    'requires-recent-login' => needsRecentSignIn,
    'network-request-failed' => network,
    _ => other,
  };
}

class ReauthException implements Exception {
  ReauthException(this.error, [this.detail]);

  final ReauthError error;
  final String? detail;

  String get message => error.message;

  @override
  String toString() => 'ReauthException(${error.name}: $detail)';
}

/// Confirms the signed-in account with something a new owner of the phone
/// number wouldn't have: its password, or its Google account. Also adds a
/// recovery email (an email/password sign-in) to an account without one.
///
/// Behind an interface so tests can fake it.
///
/// Why not an emailed sign-in link: `sendSignInLinkToEmail` works in
/// firebase_auth 5.7 (with `ActionCodeSettings.linkDomain`, now that
/// Dynamic Links are gone), but opening the link in the app needs Android
/// App Links: an intent filter for the Hosting domain, its
/// `assetlinks.json` on Firebase Hosting, and a deep-link plugin to hand the
/// URL to Dart. The app has none of these yet, so the password and Google
/// account re-check stand in. A link-based [AccountReauth] could be added
/// later without touching the screens.
abstract class AccountReauth {
  /// What the account has linked right now.
  ReauthOptions options();

  /// Re-checks the account's email/password. Throws [ReauthException].
  Future<void> withPassword(String password);

  /// Re-signs in with Google; the account must be the one linked here.
  /// False if the picker was closed. Throws [ReauthException].
  Future<bool> withGoogle();

  /// Emails a password reset link to the account's email.
  Future<void> sendPasswordReset();

  /// Links an email/password sign-in, so it can confirm new phones, and
  /// sends a verification email. Throws [ReauthException].
  Future<void> addRecoveryEmail({
    required String email,
    required String password,
  });
}

/// [AccountReauth] with Firebase Auth and google_sign_in.
class FirebaseAccountReauth implements AccountReauth {
  FirebaseAccountReauth({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
    : _authOverride = auth,
      _googleOverride = googleSignIn;

  final FirebaseAuth? _authOverride;
  final GoogleSignIn? _googleOverride;

  // Looked up on first use, so building the Us tab never needs Firebase.
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  late final GoogleSignIn _google =
      _googleOverride ?? GoogleSignIn(scopes: const ['email']);

  User _user() {
    final user = _auth.currentUser;
    if (user == null) throw ReauthException(ReauthError.other, 'signed out');
    return user;
  }

  @override
  ReauthOptions options() {
    final User? user;
    try {
      user = _auth.currentUser;
    } catch (_) {
      return ReauthOptions.none; // Firebase not ready
    }
    if (user == null) return ReauthOptions.none;
    String? password;
    String? google;
    for (final info in user.providerData) {
      if (info.providerId == EmailAuthProvider.PROVIDER_ID) {
        password = info.email ?? user.email;
      } else if (info.providerId == GoogleAuthProvider.PROVIDER_ID) {
        google = info.email ?? user.email;
      }
    }
    return ReauthOptions(passwordEmail: password, googleEmail: google);
  }

  @override
  Future<void> withPassword(String password) async {
    final email = options().passwordEmail;
    if (email == null) throw ReauthException(ReauthError.other, 'no email');
    try {
      await _user().reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
    } on FirebaseAuthException catch (e) {
      throw ReauthException(ReauthError.fromCode(e.code), e.message);
    }
  }

  @override
  Future<bool> withGoogle() async {
    try {
      // Always show the account picker, not a cached choice.
      await _google.signOut();
    } catch (_) {}
    final GoogleSignInAccount? account;
    try {
      account = await _google.signIn();
    } catch (e) {
      throw ReauthException(ReauthError.other, '$e');
    }
    if (account == null) return false;
    try {
      final tokens = await account.authentication;
      // Firebase refuses ('user-mismatch') a different Google account.
      await _user().reauthenticateWithCredential(
        GoogleAuthProvider.credential(
          idToken: tokens.idToken,
          accessToken: tokens.accessToken,
        ),
      );
      return true;
    } on FirebaseAuthException catch (e) {
      throw ReauthException(ReauthError.fromCode(e.code), e.message);
    }
  }

  @override
  Future<void> sendPasswordReset() async {
    final email = options().passwordEmail;
    if (email == null) return;
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw ReauthException(ReauthError.fromCode(e.code), e.message);
    }
  }

  @override
  Future<void> addRecoveryEmail({
    required String email,
    required String password,
  }) async {
    final user = _user();
    try {
      await user.linkWithCredential(
        EmailAuthProvider.credential(email: email.trim(), password: password),
      );
    } on FirebaseAuthException catch (e) {
      throw ReauthException(ReauthError.fromCode(e.code), e.message);
    }
    try {
      await _auth.currentUser?.sendEmailVerification();
    } catch (e) {
      // The email works for confirming phones either way.
      debugPrint('recovery email verification not sent: $e');
    }
  }
}
