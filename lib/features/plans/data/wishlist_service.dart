import 'package:couple_app/core/backend/backend.dart';

import 'package:couple_app/features/plans/models/wishlist_claim.dart';
import 'package:couple_app/features/plans/models/wishlist_item.dart';

/// Reads and writes `couples/{coupleId}/wishlist` and the secret
/// `couples/{coupleId}/wishlistClaims`.
///
/// Privacy: claims are only ever read with a `claimedBy == me` query, so
/// the owner of an item never asks for (and the rules never return) a
/// claim on their own wishes.
class WishlistService {
  WishlistService({Db? db}) : _db = db ?? Db.instance;

  final Db _db;

  DocumentReference<Map<String, dynamic>> _couple(String coupleId) =>
      _db.collection('couples').doc(coupleId);

  CollectionReference<Map<String, dynamic>> _items(String coupleId) =>
      _couple(coupleId).collection('wishlist');

  CollectionReference<Map<String, dynamic>> _claims(String coupleId) =>
      _couple(coupleId).collection('wishlistClaims');

  /// Both of your wishes. Split by `createdBy` and sort with
  /// [WishlistItem.sorted].
  Stream<List<WishlistItem>> watchItems(String coupleId) {
    return _items(
      coupleId,
    ).snapshots().map((snap) => snap.docs.map(WishlistItem.fromDoc).toList());
  }

  /// Adds [item] when its id is empty, otherwise updates what the editor
  /// can change. Only the owner may call this (enforced by the rules).
  Future<void> save(String coupleId, WishlistItem item) async {
    if (item.id.isEmpty) {
      await _items(coupleId).add({
        ...item.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _items(coupleId).doc(item.id).set({
        ...item.toEditableMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// The owner marks that they got it (or not).
  Future<void> setReceived({
    required String coupleId,
    required String itemId,
    required bool received,
  }) {
    return _items(coupleId).doc(itemId).update({
      'received': received,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String coupleId, String itemId) {
    return _items(coupleId).doc(itemId).delete();
  }

  /// The claims [myUid] has made, keyed by item id. The `claimedBy` filter
  /// is required: the rules reject any query that could return someone
  /// else's claims.
  Stream<Map<String, WishlistClaim>> watchMyClaims(
    String coupleId,
    String myUid,
  ) {
    return _claims(coupleId)
        .where('claimedBy', isEqualTo: myUid)
        .snapshots()
        .map(
          (snap) =>
              WishlistClaim.byItem(snap.docs.map(WishlistClaim.fromDoc), myUid),
        );
  }

  /// Secretly says "I'll get this" for the partner's [item].
  ///
  /// The claim lives at `wishlistClaims/{item.id}` with
  /// `claimedBy == myUid` and `itemOwner == item.createdBy`, as the rules
  /// require. It is a plain create (no read first, which the rules would
  /// refuse for a claim that is not ours).
  Future<void> claim({
    required String coupleId,
    required WishlistItem item,
    required String myUid,
  }) async {
    if (item.createdBy.isEmpty || item.createdBy == myUid) {
      throw ArgumentError('You can only claim your partner\'s wishes.');
    }
    final claim = WishlistClaim(
      itemId: item.id,
      claimedBy: myUid,
      itemOwner: item.createdBy,
    );
    final ref = _claims(coupleId).doc(item.id);
    try {
      await ref.set({
        ...claim.toMap(),
        'claimedAt': FieldValue.serverTimestamp(),
      });
    } on DbException catch (e) {
      // Writing over an existing claim counts as an update, which the rules
      // refuse. If that claim is already mine (another device, a retry),
      // there is nothing to do.
      if (e.code != 'permission-denied') rethrow;
      final existing = await ref.get();
      if (existing.data()?['claimedBy'] != myUid) rethrow;
    }
  }

  /// Marks my claim as bought (or not). Only `purchased` changes.
  Future<void> markPurchased({
    required String coupleId,
    required String itemId,
    required bool purchased,
  }) {
    return _claims(coupleId).doc(itemId).update({'purchased': purchased});
  }

  /// Gives up my claim.
  Future<void> unclaim({required String coupleId, required String itemId}) {
    return _claims(coupleId).doc(itemId).delete();
  }
}
