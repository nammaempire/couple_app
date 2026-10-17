import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/avatar/providers/avatar_providers.dart';

/// The two avatars to draw on a sticker sent by [senderId]: the sender's
/// on the left and the other partner's on the right, so a sticker looks
/// the same on both phones. Either may be null (no avatar made yet).
final stickerAvatarsProvider = Provider.autoDispose
    .family<({AvatarConfig? sender, AvatarConfig? partner}), String>((
      ref,
      senderId,
    ) {
      final mine = ref.watch(myAvatarProvider);
      final theirs = ref.watch(partnerAvatarProvider);
      final sentByMe = senderId == ref.watch(currentUidProvider);
      return sentByMe
          ? (sender: mine, partner: theirs)
          : (sender: theirs, partner: mine);
    });
