import 'package:couple_app/core/backend/backend.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/together/data/reminder_service.dart';

/// Thrown when Google sign-in cannot complete for a reason worth explaining.
class GoogleSignInSetupException implements Exception {
  GoogleSignInSetupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Email/password and Google auth, plus the matching `users/{uid}` profile.
/// Mobile-number sign-in goes through `PhoneAuthGateway`, then
/// [ensureProfile].
class AuthService {
  AuthService({FirebaseAuth? auth, Db? db, GoogleSignIn? googleSignIn})
    : _auth = auth ?? FirebaseAuth.instance,
      _db = db ?? Db.instance,
      _google = googleSignIn ?? GoogleSignIn(scopes: const ['email']);

  final FirebaseAuth _auth;
  final Db _db;
  final GoogleSignIn _google;

  User? get currentUser => _auth.currentUser;

  String? get uid => _auth.currentUser?.uid;

  /// Emits on sign-in and sign-out.
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  /// Live profile document for the signed-in user (includes `coupleId`).
  Stream<AppUser?> watchProfile(String uid) {
    return _userDoc(
      uid,
    ).snapshots().map((doc) => doc.exists ? AppUser.fromDoc(doc) : null);
  }

  Future<AppUser> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final uid = cred.user!.uid;
    await cred.user!.updateDisplayName(displayName.trim());

    final user = AppUser(
      uid: uid,
      displayName: displayName.trim(),
      profileComplete: false,
      setupComplete: false,
    );
    await _userDoc(
      uid,
    ).set(_newProfile(displayName: displayName.trim(), email: email.trim()));
    return user;
  }

  Future<void> signIn({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = _auth.currentUser!;
    await _ensureProfile(user, email: email.trim());
  }

  /// Signs in with a Google account. Returns false if the user closed the
  /// account picker.
  Future<bool> signInWithGoogle() async {
    final GoogleSignInAccount? account;
    try {
      account = await _google.signIn();
    } on Exception catch (e) {
      // Status 10 (DEVELOPER_ERROR) means this build's SHA-1 is not
      // registered in the Firebase project.
      final text = e.toString();
      if (text.contains('ApiException: 10')) {
        throw GoogleSignInSetupException(
          'Google sign-in is not set up for this build yet. '
          'Add the app\'s SHA-1 fingerprint in Firebase and try again.',
        );
      }
      rethrow;
    }
    if (account == null) return false;

    final tokens = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: tokens.idToken,
      accessToken: tokens.accessToken,
    );
    final result = await _auth.signInWithCredential(credential);

    await _ensureProfile(
      result.user!,
      email: account.email,
      displayName: account.displayName,
      photoUrl: account.photoUrl,
    );
    return true;
  }

  /// Makes sure the signed-in user has a profile document, e.g. after
  /// signing in with a mobile number for the first time. Returns their uid,
  /// or null when nobody is signed in.
  Future<String?> ensureProfile() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    await _ensureProfile(user);
    return user.uid;
  }

  /// Creates a profile document for a first-time sign-in. Existing profiles
  /// are left untouched.
  Future<void> _ensureProfile(
    User user, {
    String? email,
    String? displayName,
    String? photoUrl,
  }) async {
    final ref = _userDoc(user.uid);
    final snap = await ref.get();
    if (snap.exists) return;

    await ref.set(
      _newProfile(
        displayName: displayName ?? user.displayName ?? 'Me',
        email: email ?? user.email,
        photoUrl: photoUrl ?? user.photoURL,
      ),
    );
  }

  Map<String, dynamic> _newProfile({
    required String displayName,
    String? email,
    String? photoUrl,
  }) {
    return {
      'displayName': displayName,
      'photoUrl': photoUrl,
      'coupleId': null,
      'email': email,
      'profileComplete': false,
      'setupComplete': false,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// Saves the "about you" onboarding step and marks it complete.
  Future<void> saveProfile({
    required String displayName,
    String? nickname,
    DateTime? birthday,
    String? photoUrl,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final name = displayName.trim();
    final nick = nickname?.trim();

    await user.updateDisplayName(name);
    await _userDoc(user.uid).set({
      'displayName': name,
      'nickname': (nick == null || nick.isEmpty) ? null : nick,
      'birthday': birthday == null ? null : Timestamp.fromDate(birthday),
      'photoUrl': ?photoUrl,
      'email': user.email,
      'profileComplete': true,
    }, SetOptions(merge: true));
  }

  /// Renames the signed-in user, in both the auth record and their profile.
  Future<void> updateDisplayName(String displayName) async {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return;

    final user = _auth.currentUser;
    if (user == null) return;

    await user.updateDisplayName(trimmed);
    await _userDoc(
      user.uid,
    ).set({'displayName': trimmed}, SetOptions(merge: true));
  }

  Future<void> setBirthday(DateTime? birthday) => _mergeMine({
    'birthday': birthday == null ? null : Timestamp.fromDate(birthday),
  });

  Future<void> saveNotificationPrefs(NotificationPrefs prefs) =>
      _mergeMine({'notificationPrefs': prefs.toMap()});

  /// Records that the user confirmed they are 18 or older (for the private
  /// vault, when no birthday is set).
  Future<void> confirmAdult() =>
      _mergeMine({'adultConfirmedAt': FieldValue.serverTimestamp()});

  Future<void> markPrivacyReviewed() => _mergeMine({'privacyReviewed': true});

  /// Finishes (or skips) the post-pairing setup checklist.
  Future<void> completeSetup() => _mergeMine({'setupComplete': true});

  Future<void> _mergeMine(Map<String, dynamic> data) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _userDoc(uid).set(data, SetOptions(merge: true));
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() async {
    // Reminders belong to this account; don't leave them on the phone.
    await ReminderService.instance.clear();
    try {
      // Clears the cached Google account so the picker shows next time.
      await _google.signOut();
    } catch (_) {
      // Not signed in with Google; nothing to clear.
    }
    await _auth.signOut();
  }
}
