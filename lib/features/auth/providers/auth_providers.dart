import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/data/auth_service.dart';
import 'package:couple_app/features/auth/models/app_user.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// The Firebase user, or null when signed out.
final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(authServiceProvider).authStateChanges(),
);

/// A user's live profile. Null until the profile document exists.
final profileProvider = StreamProvider.autoDispose.family<AppUser?, String>(
  (ref, uid) => ref.watch(authServiceProvider).watchProfile(uid),
);

/// The signed-in user's profile.
///
/// Only read this below [AuthGate]'s signed-in branches, where the profile
/// has loaded. While signing out, or if the profile document briefly
/// disappears, it keeps the last profile it had for the same user, so
/// screens that are still mounted (including pushed routes) never see a
/// missing user. Reading it before any profile has loaded throws.
final currentUserProvider =
    NotifierProvider.autoDispose<CurrentUserNotifier, AppUser>(
      CurrentUserNotifier.new,
    );

class CurrentUserNotifier extends Notifier<AppUser> {
  @override
  AppUser build() {
    final uid = ref.watch(authStateProvider).value?.uid;
    final profile = uid == null ? null : ref.watch(profileProvider(uid)).value;
    if (profile != null) return profile;

    // Signed out (uid == null) or the profile vanished: keep the last one,
    // but never hand one user's profile to a different signed-in user.
    final previous = stateOrNull;
    if (previous != null && (uid == null || uid == previous.uid)) {
      return previous;
    }
    throw StateError('currentUserProvider was read with no signed-in profile.');
  }
}

/// The signed-in user's id. Unlike [currentUserProvider], it does not
/// change when other profile fields do.
final currentUidProvider = Provider.autoDispose<String>(
  (ref) => ref.watch(currentUserProvider.select((user) => user.uid)),
);

/// The id of the couple the signed-in user belongs to.
///
/// Only read this once the user has joined a couple.
final currentCoupleIdProvider = Provider.autoDispose<String>((ref) {
  final coupleId = ref.watch(
    currentUserProvider.select((user) => user.coupleId),
  );
  if (coupleId == null) {
    throw StateError('currentCoupleIdProvider was read before pairing.');
  }
  return coupleId;
});
