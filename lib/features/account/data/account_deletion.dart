import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:couple_app/core/backend/backend.dart';

/// Why deleting the account didn't go through.
enum AccountDeletionFailure {
  /// The sign-in is too old: confirm it's you again, then retry.
  needsRecentSignIn,

  /// The pairing is being ended or changed right now: retry shortly.
  busy,

  /// No connection, or the server couldn't be reached.
  unavailable,
  other;

  String get message => switch (this) {
    needsRecentSignIn =>
      'For your safety, confirm it\'s you again, then delete.',
    busy => 'Your pairing is being changed right now. Try again in a minute.',
    unavailable => 'No connection. Check your network and try again.',
    other => 'Something went wrong. Please try again.',
  };
}

class AccountDeletionException implements Exception {
  AccountDeletionException(this.failure, [this.detail]);

  final AccountDeletionFailure failure;
  final String? detail;

  String get message => failure.message;

  @override
  String toString() => 'AccountDeletionException(${failure.name}: $detail)';
}

/// Deletes the signed-in account for good: the server ends the pairing
/// (everything the couple shared is deleted for both), deletes this
/// person's data and files and their sign-in. Behind an interface so tests
/// can fake it.
abstract class AccountDeletionGateway {
  /// Returns true when the server also deleted the sign-in.
  Future<bool> deleteOnServer();

  /// Deletes the sign-in from the phone when the server couldn't.
  Future<void> deleteSignInHere();
}

/// [AccountDeletionGateway] through the `deleteAccount` server function.
class FunctionsAccountDeletionGateway implements AccountDeletionGateway {
  FunctionsAccountDeletionGateway({Functions? functions, FirebaseAuth? auth})
    : _givenFunctions = functions,
      _givenAuth = auth;

  final Functions? _givenFunctions;
  final FirebaseAuth? _givenAuth;

  late final Functions _functions = _givenFunctions ?? Functions.instance;
  FirebaseAuth get _auth => _givenAuth ?? FirebaseAuth.instance;

  @override
  Future<bool> deleteOnServer() async {
    try {
      // The ID token sent with the call must carry the new sign-in time.
      await _auth.currentUser?.getIdToken(true);
    } catch (_) {}
    try {
      final result = await _functions.call('deleteAccount', {
        'confirm': 'DELETE',
      });
      return result is Map && result['signInDeleted'] == true;
    } on FunctionsException catch (e) {
      throw AccountDeletionException(failureFor(e.code), e.message);
    } catch (e) {
      throw AccountDeletionException(AccountDeletionFailure.unavailable, '$e');
    }
  }

  @override
  Future<void> deleteSignInHere() async {
    try {
      await _auth.currentUser?.delete();
    } catch (e) {
      // The data is already gone; a leftover sign-in just opens a fresh,
      // empty account if used again.
      debugPrint('could not delete the sign-in on the phone: $e');
    }
  }

  @visibleForTesting
  static AccountDeletionFailure failureFor(String code) => switch (code) {
    'failed-precondition' => AccountDeletionFailure.needsRecentSignIn,
    'aborted' => AccountDeletionFailure.busy,
    'unavailable' || 'deadline-exceeded' => AccountDeletionFailure.unavailable,
    _ => AccountDeletionFailure.other,
  };
}
