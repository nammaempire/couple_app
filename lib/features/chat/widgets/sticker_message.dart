import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/stickers/data/sticker_catalog.dart';
import 'package:couple_app/features/stickers/providers/sticker_providers.dart';
import 'package:couple_app/features/stickers/widgets/couple_sticker_view.dart';

/// A sticker message's picture: the sender on the left, their partner on
/// the right, so it looks the same on both phones.
class StickerMessage extends ConsumerWidget {
  const StickerMessage({super.key, required this.message, this.width = 240});

  final Message message;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatars = ref.watch(stickerAvatarsProvider(message.senderId));
    // Its own layer, so chat scrolling and bubble changes don't repaint it.
    return RepaintBoundary(
      child: CoupleStickerView(
        scene: StickerCatalog.resolve(
          message.stickerId,
          message.stickerCategory,
        ),
        sender: avatars.sender,
        partner: avatars.partner,
        quote: message.text,
        width: width,
      ),
    );
  }
}
