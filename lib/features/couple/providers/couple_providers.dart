import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/data/couple_service.dart';
import 'package:couple_app/features/couple/models/couple.dart';

final coupleServiceProvider = Provider<CoupleService>((ref) => CoupleService());

/// The signed-in user's couple. Null if the document no longer exists.
final coupleProvider = StreamProvider.autoDispose<Couple?>(
  (ref) => ref
      .watch(coupleServiceProvider)
      .watchCouple(ref.watch(currentCoupleIdProvider)),
);

/// The partner's live profile, once they have joined.
///
/// Missing profiles are skipped, so the last known profile stays in place.
final partnerProvider = StreamProvider.autoDispose<AppUser?>((ref) {
  final uid = ref.watch(currentUidProvider);
  final partnerId = ref.watch(
    coupleProvider.select((couple) => couple.value?.partnerIdFor(uid)),
  );
  if (partnerId == null) return const Stream.empty();
  return ref
      .watch(coupleServiceProvider)
      .watchUser(partnerId)
      .where((user) => user != null);
});

/// What this user calls their partner: their own nickname for them, else
/// the partner's display name.
final partnerNameProvider = Provider.autoDispose<String>((ref) {
  final uid = ref.watch(currentUidProvider);
  final nickname = ref.watch(
    coupleProvider.select((couple) => couple.value?.nicknameChosenBy(uid)),
  );
  return nickname ??
      ref.watch(partnerProvider).value?.displayName ??
      'Your partner';
});
