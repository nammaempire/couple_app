import 'package:couple_app/core/backend/backend.dart';

import 'package:couple_app/features/auth/data/phone_number_service.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/couple/data/couple_service.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/models/invite.dart';
import 'package:couple_app/features/couple/models/pair_request.dart';

/// The result of asking to pair with a mobile number.
sealed class PairByNumberOutcome {
  const PairByNumberOutcome();
}

/// Nobody has verified that number in the app: share an invite instead.
class PairByNumberNotJoined extends PairByNumberOutcome {
  const PairByNumberNotJoined();
}

/// The request is waiting for them.
class PairByNumberSent extends PairByNumberOutcome {
  const PairByNumberSent(this.requestId);
  final String requestId;
}

/// Pairing with someone's mobile number, through `pairRequests`.
///
/// The sender only ever learns "they haven't joined" or a generic
/// [couldNotPair]; whether the other person is already paired is never
/// revealed to them. Only the number's owner hears "This number is already
/// paired".
class PairRequestService {
  PairRequestService({
    Db? db,
    CoupleService? couples,
    PhoneNumberService? phones,
  }) : _db = db ?? Db.instance,
       _couples = couples ?? CoupleService(db: db),
       _phones = phones ?? PhoneNumberService(db: db);

  final Db _db;
  final CoupleService _couples;
  final PhoneNumberService _phones;

  /// The only failure the sender is ever shown.
  static const couldNotPair = 'Couldn\'t pair with this number.';

  /// Shown only to the owner of the number.
  static const alreadyPaired = 'This number is already paired.';

  CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection('pairRequests');

  /// Pending requests to [uid].
  Stream<List<PairRequest>> watchIncoming(String uid) => _requests
      .where('toUid', isEqualTo: uid)
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map(_sorted);

  /// Every request from [uid], newest first.
  Stream<List<PairRequest>> watchOutgoing(String uid) =>
      _requests.where('fromUid', isEqualTo: uid).snapshots().map(_sorted);

  static List<PairRequest> _sorted(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = snap.docs.map(PairRequest.fromDoc).toList();
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    list.sort((a, b) => (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch));
    return list;
  }

  /// Asks the owner of [toPhone] (E.164) to pair with [me].
  ///
  /// [myCouple] is [me]'s couple of one, if they already made one; if they
  /// have none, one is created first, as "Create our space" does. Throws a
  /// [PairingException] with [couldNotPair] (or "that's your own number").
  Future<PairByNumberOutcome> requestByNumber({
    required AppUser me,
    required String toPhone,
    Couple? myCouple,
  }) async {
    if (me.phone != null && me.phone == toPhone) {
      throw PairingException('That\'s your own number.');
    }
    try {
      final toUid = await _phones.lookup(toPhone);
      if (toUid == null) return const PairByNumberNotJoined();
      if (toUid == me.uid) throw PairingException('That\'s your own number.');

      // Asked already: keep the one request.
      final mine = await _requests.where('fromUid', isEqualTo: me.uid).get();
      for (final doc in mine.docs) {
        final r = PairRequest.fromDoc(doc);
        if (r.isPending && r.toUid == toUid) return PairByNumberSent(r.id);
      }

      final Couple couple;
      if (myCouple != null) {
        if (myCouple.memberIds.length != 1 ||
            myCouple.memberIds.first != me.uid) {
          throw PairingException(couldNotPair);
        }
        couple = myCouple;
      } else if (me.coupleId == null) {
        couple = await _couples.createCouple(
          me.uid,
          inviterName: me.displayName,
          inviterPhotoUrl: me.photoUrl,
        );
      } else {
        throw PairingException(couldNotPair);
      }

      final name = me.displayName.trim();
      final ref = await _requests.add({
        'fromUid': me.uid,
        'fromName': name.length > PairRequest.maxNameLength
            ? name.substring(0, PairRequest.maxNameLength)
            : name,
        'fromPhone': me.phone ?? '',
        'toUid': toUid,
        'toPhone': toPhone,
        'coupleId': couple.id,
        'inviteCode': couple.inviteCode,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return PairByNumberSent(ref.id);
    } on PairingException {
      rethrow;
    } catch (_) {
      throw PairingException(couldNotPair);
    }
  }

  /// Accepts [request] for [uid]: joins the sender's couple with its invite
  /// code (the same transaction as typing the code), then marks the request
  /// accepted.
  ///
  /// [myCouple] is [uid]'s current couple, if any. A couple of one (their
  /// own waiting invite) is cancelled first; a complete one means they are
  /// already paired, which is only ever said to them.
  Future<void> accept({
    required String uid,
    required PairRequest request,
    Couple? myCouple,
  }) async {
    if (myCouple != null && myCouple.isComplete) {
      throw PairingException(alreadyPaired);
    }

    final Invite invite;
    try {
      invite = await _couples.lookupInvite(uid: uid, code: request.inviteCode);
    } catch (_) {
      throw PairingException(
        'This request is no longer available. Ask ${request.fromName} to '
        'send a new one.',
      );
    }
    if (invite.coupleId != request.coupleId) {
      throw PairingException('This request is no longer available.');
    }

    if (myCouple != null) {
      await _couples.cancelWaitingCouple(uid: uid, couple: myCouple);
    }
    try {
      await _couples.acceptInvite(uid: uid, invite: invite);
    } on PairingException {
      rethrow;
    } catch (_) {
      throw PairingException('Could not connect. Try again.');
    }

    // Best effort: the pairing itself is done.
    try {
      await _requests.doc(request.id).update({'status': 'accepted'});
    } catch (_) {}
    // Requests this user sent from their own waiting space are moot now.
    try {
      final mine = await _requests.where('fromUid', isEqualTo: uid).get();
      for (final doc in mine.docs) {
        if (PairRequest.fromDoc(doc).isPending) {
          await doc.reference.update({'status': 'cancelled'});
        }
      }
    } catch (_) {}
  }

  /// The receiver says no.
  Future<void> decline(PairRequest request) =>
      _requests.doc(request.id).update({'status': 'declined'});

  /// The sender withdraws a pending request.
  Future<void> cancel(PairRequest request) =>
      _requests.doc(request.id).update({'status': 'cancelled'});

  /// The sender clears a finished request from their screen.
  Future<void> dismiss(PairRequest request) =>
      _requests.doc(request.id).delete();
}
