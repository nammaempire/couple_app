import 'package:cloud_firestore/cloud_firestore.dart';

/// A secret "I'll get this" on one of the partner's wishes, stored at
/// `wishlistClaims/{itemId}`. Only [claimedBy] can ever read it; the item
/// owner never sees it.
class WishlistClaim {
  /// The wishlist item's id (claims share the item's document id).
  final String itemId;
  final String claimedBy;

  /// The item's owner, who must not find out.
  final String itemOwner;

  final DateTime? claimedAt;
  final bool purchased;

  const WishlistClaim({
    required this.itemId,
    required this.claimedBy,
    required this.itemOwner,
    this.claimedAt,
    this.purchased = false,
  });

  factory WishlistClaim.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      fromMap(doc.id, doc.data() ?? <String, dynamic>{});

  static WishlistClaim fromMap(String itemId, Map<String, dynamic> data) {
    final at = data['claimedAt'];
    return WishlistClaim(
      itemId: itemId,
      claimedBy: data['claimedBy'] is String ? data['claimedBy'] as String : '',
      itemOwner: data['itemOwner'] is String ? data['itemOwner'] as String : '',
      claimedAt: at is Timestamp ? at.toDate() : (at is DateTime ? at : null),
      purchased: data['purchased'] == true,
    );
  }

  /// The stored fields, without `claimedAt` (the service sets it from the
  /// server clock).
  Map<String, dynamic> toMap() => {
    'claimedBy': claimedBy,
    'itemOwner': itemOwner,
    'purchased': purchased,
  };

  /// My claims keyed by item id, ignoring any that are not mine (defensive;
  /// the query already filters on claimedBy).
  static Map<String, WishlistClaim> byItem(
    Iterable<WishlistClaim> claims,
    String myUid,
  ) => {
    for (final c in claims)
      if (c.claimedBy == myUid) c.itemId: c,
  };
}
