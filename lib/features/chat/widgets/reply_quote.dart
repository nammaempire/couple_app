import 'package:flutter/material.dart';

import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/widgets/chat_palette.dart';
import 'package:couple_app/features/chat/widgets/sticker_reply_thumb.dart';

/// The quoted message at the top of a reply.
class ReplyQuote extends StatelessWidget {
  const ReplyQuote({
    super.key,
    required this.reply,
    required this.label,
    required this.onMine,
    this.onTap,
  });

  final ReplyPreview reply;
  final String label;

  /// Drawn inside one of my (coloured) bubbles.
  final bool onMine;
  final VoidCallback? onTap;

  /// The sticker marker [ReplyPreview.text] starts with for stickers.
  static const _stickerMark = '💞 ';

  /// The quoted text as shown. Next to a sticker thumbnail the stored
  /// "💞 " marker would say "sticker" twice, so it's left off.
  static String previewFor(ReplyPreview reply, {required bool withThumb}) {
    var text = reply.text;
    if (withThumb && text.startsWith(_stickerMark)) {
      text = text.substring(_stickerMark.length).trim();
      if (text.isEmpty) return 'Sticker';
    }
    return text.isEmpty ? 'Message' : text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = ChatPalette.of(context);
    final accent = onMine ? palette.onMine : theme.colorScheme.primary;
    final textColor = onMine
        ? palette.onMine.withValues(alpha: .88)
        : theme.colorScheme.onSurfaceVariant;
    final isSticker =
        reply.type == MessageType.sticker && reply.stickerId != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: onMine
              ? Colors.white.withValues(alpha: .16)
              : theme.colorScheme.primary.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSticker) ...[
              StickerReplyThumb(reply: reply),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    previewFor(reply, withThumb: isSticker),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
