import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/avatar/data/avatar_service.dart';
import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';

final avatarServiceProvider = Provider<AvatarService>((ref) => AvatarService());

/// My avatar, or null if I haven't made one.
final myAvatarProvider = Provider.autoDispose<AvatarConfig?>(
  (ref) => ref.watch(currentUserProvider.select((u) => u.avatar)),
);

/// My partner's avatar, or null if they haven't made one (or haven't
/// joined yet).
final partnerAvatarProvider = Provider.autoDispose<AvatarConfig?>(
  (ref) => ref.watch(partnerProvider).value?.avatar,
);
