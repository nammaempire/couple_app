import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/stickers/data/sticker_catalog.dart';
import 'package:couple_app/features/stickers/providers/sticker_providers.dart';
import 'package:couple_app/features/stickers/widgets/couple_sticker_view.dart';

/// A small picture of a quoted sticker, without its quote.
class StickerReplyThumb extends ConsumerWidget {
  const StickerReplyThumb({super.key, required this.reply, this.width = 52});

  final ReplyPreview reply;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatars = ref.watch(stickerAvatarsProvider(reply.senderId));
    return CoupleStickerView(
      scene: StickerCatalog.resolve(reply.stickerId, reply.stickerCategory),
      sender: avatars.sender,
      partner: avatars.partner,
      quote: '',
      width: width,
      showQuote: false,
    );
  }
}
