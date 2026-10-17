import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/plans/data/wishlist_service.dart';
import 'package:couple_app/features/plans/models/wishlist_claim.dart';
import 'package:couple_app/features/plans/models/wishlist_item.dart';

final wishlistServiceProvider = Provider<WishlistService>(
  (ref) => WishlistService(),
);

/// Both partners' wishes, unordered. Split by `createdBy` and sort with
/// `WishlistItem.sorted`.
final wishlistItemsProvider = StreamProvider.autoDispose<List<WishlistItem>>(
  (ref) => ref
      .watch(wishlistServiceProvider)
      .watchItems(ref.watch(currentCoupleIdProvider)),
);

/// The signed-in user's secret claims on their partner's wishes, keyed by
/// item id. Never use this to show anything on the user's own wishes.
final myWishlistClaimsProvider =
    StreamProvider.autoDispose<Map<String, WishlistClaim>>(
      (ref) => ref
          .watch(wishlistServiceProvider)
          .watchMyClaims(
            ref.watch(currentCoupleIdProvider),
            ref.watch(currentUidProvider),
          ),
    );
