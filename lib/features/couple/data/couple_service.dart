import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/models/invite.dart';

/// Thrown when joining with a code that is invalid or already used up.
class PairingException implements Exception {
  PairingException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Creates and joins the two-person "couple" that owns a conversation.
class CoupleService {
  CoupleService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  String _generateCode() {
    final rand = Random.secure();
    return List.generate(
      InviteCode.length,
      (_) => InviteCode.alphabet[rand.nextInt(InviteCode.alphabet.length)],
    ).join();
  }

  Stream<Couple?> watchCouple(String coupleId) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .snapshots()
        .map((doc) => doc.exists ? Couple.fromDoc(doc) : null);
  }

  /// Live profile of [uid] — used for the partner's name, photo and birthday.
  Stream<AppUser?> watchUser(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? AppUser.fromDoc(doc) : null);
  }

  DocumentReference<Map<String, dynamic>> _inviteDoc(String code) =>
      _db.collection('invites').doc(code);

  /// Creates a new couple owned by [uid], plus its single-use invite.
  ///
  /// The couple, the invite and the user's `coupleId` are written in one
  /// batch. If the random code happens to collide with an existing invite the
  /// rules reject the batch, so a fresh code is tried.
  Future<Couple> createCouple(
    String uid, {
    required String inviterName,
    String? inviterPhotoUrl,
    String? coupleName,
    DateTime? startDate,
  }) async {
    final name = coupleName?.trim();
    FirebaseException? lastError;

    for (var attempt = 0; attempt < 3; attempt++) {
      final coupleRef = _db.collection('couples').doc();
      final code = _generateCode();

      final batch = _db.batch();
      batch.set(coupleRef, {
        'inviteCode': code,
        'memberIds': [uid],
        'createdAt': FieldValue.serverTimestamp(),
        'coupleName': (name == null || name.isEmpty) ? null : name,
        'startDate': startDate == null ? null : Timestamp.fromDate(startDate),
      });
      batch.set(_inviteDoc(code), {
        'coupleId': coupleRef.id,
        'createdBy': uid,
        'inviterName': inviterName,
        'inviterPhotoUrl': inviterPhotoUrl,
        'coupleName': (name == null || name.isEmpty) ? null : name,
        'used': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.update(_db.collection('users').doc(uid), {
        'coupleId': coupleRef.id,
      });

      try {
        await batch.commit();
        return Couple(
          id: coupleRef.id,
          inviteCode: code,
          memberIds: [uid],
          coupleName: name,
          startDate: startDate,
        );
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
        lastError = e;
      }
    }
    throw lastError!;
  }

  /// Makes sure the invite document for a waiting couple exists. Couples
  /// created before invites had their own collection only carry the code.
  Future<void> ensureInvite({
    required Couple couple,
    required String uid,
    required String inviterName,
    String? inviterPhotoUrl,
  }) async {
    if (couple.isComplete || couple.inviteCode.isEmpty) return;
    final ref = _inviteDoc(couple.inviteCode);
    final snap = await ref.get();
    if (snap.exists) return;

    await ref.set({
      'coupleId': couple.id,
      'createdBy': uid,
      'inviterName': inviterName,
      'inviterPhotoUrl': inviterPhotoUrl,
      'coupleName': couple.coupleName,
      'used': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Looks up an invite by its code so the joiner can see who it is from
  /// before accepting.
  Future<Invite> lookupInvite({
    required String uid,
    required String code,
  }) async {
    final normalized = code.trim().toUpperCase();
    if (!InviteCode.isValid(normalized)) {
      throw PairingException('That code should be 6 letters and numbers.');
    }

    final snap = await _inviteDoc(normalized).get();
    if (!snap.exists) {
      throw PairingException('No invite found for code $normalized.');
    }

    final invite = Invite.fromDoc(snap);
    if (invite.createdBy == uid) {
      throw PairingException(
        'That is your own code. Send it to your partner to enter on their phone.',
      );
    }
    if (invite.used) {
      throw PairingException('That invite has already been used.');
    }
    return invite;
  }

  /// Accepts [invite]: adds [uid] to the couple, marks the invite used, and
  /// links the user's profile, all in one transaction.
  ///
  /// The joiner cannot read the couple before joining, so the "couple already
  /// has two people" check is enforced by the security rules; a rejection
  /// surfaces as an already-used error.
  Future<void> acceptInvite({
    required String uid,
    required Invite invite,
  }) async {
    final inviteRef = _inviteDoc(invite.code);
    final coupleRef = _db.collection('couples').doc(invite.coupleId);
    final userRef = _db.collection('users').doc(uid);

    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(inviteRef);
        if (!snap.exists) {
          throw PairingException('That invite was cancelled.');
        }
        if ((snap.data()?['used'] as bool?) ?? false) {
          throw PairingException('That invite has already been used.');
        }

        tx.update(coupleRef, {
          'memberIds': FieldValue.arrayUnion([uid]),
          'activatedAt': FieldValue.serverTimestamp(),
        });
        tx.update(inviteRef, {
          'used': true,
          'usedBy': uid,
          'usedAt': FieldValue.serverTimestamp(),
        });
        tx.update(userRef, {'coupleId': invite.coupleId});
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw PairingException('That invite can no longer be used.');
      }
      rethrow;
    }
  }

  /// Deletes a couple that is still waiting for a partner, along with its
  /// invite, so this user can join someone else's code instead.
  Future<void> cancelWaitingCouple({
    required String uid,
    required Couple couple,
  }) async {
    if (couple.isComplete) return;

    // Couples from before invites had their own collection have no invite
    // document, and the rules refuse deleting a document that is not there.
    final inviteRef = couple.inviteCode.isEmpty
        ? null
        : _inviteDoc(couple.inviteCode);
    final inviteExists = inviteRef != null && (await inviteRef.get()).exists;

    final batch = _db.batch();
    if (inviteExists) batch.delete(inviteRef);
    batch.delete(_db.collection('couples').doc(couple.id));
    batch.update(_db.collection('users').doc(uid), {'coupleId': null});
    await batch.commit();
  }

  /// Currency for shared expenses, as an ISO 4217 code such as `INR`.
  Future<void> setCurrency({
    required String coupleId,
    required String currency,
  }) {
    return _db.collection('couples').doc(coupleId).set({
      'currency': currency,
    }, SetOptions(merge: true));
  }

  Future<void> setCoupleName({
    required String coupleId,
    required String? name,
  }) {
    final trimmed = name?.trim();
    return _db.collection('couples').doc(coupleId).set({
      'coupleName': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
    }, SetOptions(merge: true));
  }

  Future<void> setCouplePhoto({
    required String coupleId,
    required String photoUrl,
  }) {
    return _db.collection('couples').doc(coupleId).set({
      'photoUrl': photoUrl,
    }, SetOptions(merge: true));
  }

  /// Sets the day the relationship started, for the days-together counter.
  Future<void> setStartDate({
    required String coupleId,
    required DateTime? date,
  }) {
    return _db.collection('couples').doc(coupleId).set({
      'startDate': date == null ? null : Timestamp.fromDate(date),
    }, SetOptions(merge: true));
  }

  /// Sets the next date the two of you will be together.
  Future<void> setNextMeetup({
    required String coupleId,
    required DateTime? date,
  }) {
    return _db.collection('couples').doc(coupleId).set({
      'nextMeetup': date == null ? null : Timestamp.fromDate(date),
    }, SetOptions(merge: true));
  }

  /// Sets what [uid] calls their partner. Passing null or blank clears it,
  /// falling the app back to the partner's own display name.
  Future<void> setPartnerNickname({
    required String coupleId,
    required String uid,
    required String? nickname,
  }) {
    final trimmed = nickname?.trim();
    final ref = _db.collection('couples').doc(coupleId);

    if (trimmed == null || trimmed.isEmpty) {
      return ref.update({'nicknames.$uid': FieldValue.delete()});
    }
    return ref.set({
      'nicknames': {uid: trimmed},
    }, SetOptions(merge: true));
  }
}
