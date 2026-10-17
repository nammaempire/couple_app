import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/plans/data/bucket_list_service.dart';
import 'package:couple_app/features/plans/models/bucket_item.dart';

final bucketListServiceProvider = Provider<BucketListService>(
  (ref) => BucketListService(),
);

/// Every item on the couple's shared bucket list, unordered. Sort and
/// group with `BucketProgress`.
final bucketItemsProvider = StreamProvider.autoDispose<List<BucketItem>>(
  (ref) => ref
      .watch(bucketListServiceProvider)
      .watchItems(ref.watch(currentCoupleIdProvider)),
);
