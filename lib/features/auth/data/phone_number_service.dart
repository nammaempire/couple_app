import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:couple_app/features/auth/models/phone_number.dart';

/// Verified mobile numbers: `users/{uid}.phone` and the
/// `phoneIndex/{e164}` entry that lets a partner find you by number.
///
/// Only a number the signed-in account verified by SMS can be written; the
/// rules compare both with the ID token's `phone_number`.
class PhoneNumberService {
  PhoneNumberService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _index(String e164) =>
      _db.collection('phoneIndex').doc(e164);

  /// Records [e164] as [uid]'s number, on their profile and in the index,
  /// in one batch. A number that moved to a new owner (recycled) is simply
  /// claimed again.
  Future<void> saveVerifiedPhone({
    required String uid,
    required String e164,
  }) async {
    if (!PhoneNumbers.isE164(e164)) {
      throw ArgumentError.value(e164, 'e164', 'Not an E.164 number');
    }
    final batch = _db.batch();
    batch.set(_db.collection('users').doc(uid), {
      'phone': e164,
    }, SetOptions(merge: true));
    batch.set(_index(e164), {
      'uid': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// The account that verified [e164], or null if nobody has.
  Future<String?> lookup(String e164) async {
    final snap = await _index(e164).get();
    if (!snap.exists) return null;
    final uid = snap.data()?['uid'];
    return uid is String && uid.isNotEmpty ? uid : null;
  }
}
