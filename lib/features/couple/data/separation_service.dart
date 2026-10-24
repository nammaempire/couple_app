import 'package:couple_app/core/backend/backend.dart';

import 'package:couple_app/features/couple/models/separation.dart';

/// Thrown when a separation change isn't this user's to make, or no longer
/// applies (the other phone changed it first).
class SeparationException implements Exception {
  SeparationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Ending a pairing: asking, agreeing, declining and calling it off, on
/// `couples/{id}.separation`, plus the "mute my partner" switch and clearing
/// the "your pairing has ended" marker on the user's own profile.
///
/// The security rules allow exactly these writes, so each method checks
/// the same conditions first and explains a refusal in plain words. Dates
/// come from [clock] (the phone), which the rules accept within ten minutes
/// of the server's time.
class SeparationService {
  SeparationService({Db? db, DateTime Function()? clock})
    : _db = db ?? Db.instance,
      _clock = clock ?? DateTime.now;

  final Db _db;
  final DateTime Function() _clock;

  DocumentReference<Map<String, dynamic>> _couple(String coupleId) =>
      _db.collection('couples').doc(coupleId);

  /// Asks to end the pairing, 14 days from now.
  Future<void> request({
    required String coupleId,
    required String uid,
    required Separation? current,
  }) async {
    if (current != null) {
      throw SeparationException('Your pairing is already ending.');
    }
    await _couple(coupleId).update({
      'separation': {
        'requestedBy': uid,
        'requestedAt': FieldValue.serverTimestamp(),
        'status': 'requested',
        'agreedAt': null,
        'declinedAt': null,
        'effectiveAt': Timestamp.fromDate(
          _clock().add(Separation.waitingPeriod),
        ),
      },
    });
  }

  /// The other partner agrees: it ends 7 days from now, or on the date
  /// already set if that is sooner. Also allowed after declining.
  Future<void> agree({
    required String coupleId,
    required String uid,
    required Separation current,
  }) async {
    if (current.isRequestedBy(uid)) {
      throw SeparationException('Only your partner can agree to this.');
    }
    if (current.status == SeparationStatus.agreed) return;

    final effectiveAt = current.effectiveAtIfAgreedAt(_clock());
    await _couple(coupleId).update({
      'separation.status': 'agreed',
      'separation.agreedAt': FieldValue.serverTimestamp(),
      // Left alone when the current date is the sooner one, so it stays
      // exactly as it was.
      if (effectiveAt != current.effectiveAt)
        'separation.effectiveAt': Timestamp.fromDate(effectiveAt),
    });
  }

  /// The other partner says they don't want this. The date doesn't move.
  Future<void> decline({
    required String coupleId,
    required String uid,
    required Separation current,
  }) async {
    if (current.isRequestedBy(uid)) {
      throw SeparationException('Only your partner can answer this.');
    }
    if (current.status != SeparationStatus.requested) {
      throw SeparationException('You have already answered.');
    }
    await _couple(coupleId).update({
      'separation.status': 'declined',
      'separation.declinedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Calls it off. Only the partner who asked can.
  Future<void> cancel({
    required String coupleId,
    required String uid,
    required Separation current,
  }) async {
    if (!current.isRequestedBy(uid)) {
      throw SeparationException(
        'Only the one who asked to end your pairing can call it off.',
      );
    }
    await _couple(coupleId).update({'separation': FieldValue.delete()});
  }

  /// Turns "mute my partner" on or off for [uid].
  Future<void> setMutePartner({required String uid, required bool muted}) {
    return _db.collection('users').doc(uid).set({
      'mutePartner': muted,
    }, SetOptions(merge: true));
  }

  /// Clears the server's "your pairing has ended" marker once seen.
  Future<void> clearPairingEnded(String uid) {
    return _db.collection('users').doc(uid).update({
      'pairingEndedAt': FieldValue.delete(),
      'pairingEndedHow': FieldValue.delete(),
    });
  }
}
