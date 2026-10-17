import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/widgets/chat_palette.dart';
import 'package:couple_app/features/chat/widgets/message_media_content.dart';
import 'package:couple_app/features/chat/widgets/message_meta_row.dart';
import 'package:couple_app/features/chat/widgets/reaction_pill.dart';
import 'package:couple_app/features/chat/widgets/reply_quote.dart';
import 'package:couple_app/features/chat/widgets/sticker_message.dart';
import 'package:couple_app/features/chat/widgets/voice_message_player.dart';

/// One chat message, aligned left (partner) or right (me).
///
/// Swipe right to reply, long-press for actions, double-tap to heart.
class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.myUid,
    required this.partnerName,
    this.onLongPress,
    this.onDoubleTap,
    this.onSwipeReply,
    this.onTapQuote,
    this.highlighted = false,
  });

  final Message message;
  final bool isMine;
  final String myUid;
  final String partnerName;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;

  /// Called when the bubble is swiped far enough to start a reply.
  final VoidCallback? onSwipeReply;

  /// Called with the quoted message's id when the reply quote is tapped.
  final ValueChanged<String>? onTapQuote;

  /// Briefly tinted after jumping to this message from search, a pin or a
  /// reply quote.
  final bool highlighted;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  static const _replyThreshold = 64.0;

  double _dragX = 0;
  bool _armed = false;

  void _onDragUpdate(DragUpdateDetails details) {
    if (widget.onSwipeReply == null) return;
    setState(() {
      _dragX = (_dragX + details.delta.dx).clamp(0.0, _replyThreshold * 1.4);
    });
    final armed = _dragX >= _replyThreshold;
    if (armed && !_armed) HapticFeedback.selectionClick();
    _armed = armed;
  }

  void _onDragEnd(DragEndDetails _) {
    if (_armed) widget.onSwipeReply?.call();
    _resetDrag();
  }

  /// Also used when the gesture is cancelled, so a bubble never stays
  /// half-swiped.
  void _resetDrag() {
    if (_dragX == 0 && !_armed) return;
    setState(() {
      _dragX = 0;
      _armed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = widget.message;
    final isMine = widget.isMine;
    final palette = ChatPalette.of(context);

    final bg = isMine ? theme.colorScheme.primary : palette.theirsBubble;
    final fg = isMine ? theme.colorScheme.onPrimary : palette.onTheirsBubble;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(isMine ? 20 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 20),
    );

    final quote = message.replyTo == null
        ? null
        : ReplyQuote(
            reply: message.replyTo!,
            label: message.replyTo!.senderId == widget.myUid
                ? 'You'
                : widget.partnerName,
            onMine: isMine,
            onTap: widget.onTapQuote == null
                ? null
                : () => widget.onTapQuote!(message.replyTo!.messageId),
          );

    Widget content;
    switch (message.type) {
      case MessageType.image:
      case MessageType.video:
        content = Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (quote != null) ...[quote, const SizedBox(height: 4)],
            MessageMediaContent(
              message: message,
              radius: radius,
              isMine: isMine,
            ),
          ],
        );
      case MessageType.sticker:
        // No bubble: the sticker card is the message.
        final stickerWidth = math.min(
          250.0,
          MediaQuery.sizeOf(context).width * .66,
        );
        content = Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.replyTo != null) ...[
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: stickerWidth),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.theirsBubble,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ReplyQuote(
                    reply: message.replyTo!,
                    label: message.replyTo!.senderId == widget.myUid
                        ? 'You'
                        : widget.partnerName,
                    onMine: false,
                    onTap: widget.onTapQuote == null
                        ? null
                        : () => widget.onTapQuote!(message.replyTo!.messageId),
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
            StickerMessage(message: message, width: stickerWidth),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: palette.systemChip,
                borderRadius: BorderRadius.circular(10),
              ),
              child: MessageMetaRow(
                message: message,
                isMine: isMine,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      case MessageType.voice:
      case MessageType.text:
      case MessageType.call:
        content = Container(
          padding: EdgeInsets.fromLTRB(
            message.type == MessageType.voice ? 8 : 16,
            quote == null ? 10 : 8,
            message.type == MessageType.voice ? 12 : 16,
            8,
          ),
          decoration: BoxDecoration(color: bg, borderRadius: radius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (quote != null) ...[quote, const SizedBox(height: 6)],
              if (message.type == MessageType.voice)
                VoiceMessagePlayer(message: message, color: fg)
              else
                Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  child: Text(
                    message.text,
                    style: TextStyle(color: fg, fontSize: 16),
                  ),
                ),
              const SizedBox(height: 2),
              MessageMetaRow(
                message: message,
                isMine: isMine,
                color: fg.withValues(alpha: .7),
              ),
            ],
          ),
        );
    }

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.75,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.only(
              bottom: message.reactions.isEmpty ? 0 : 12,
            ),
            child: content,
          ),
          if (message.reactions.isNotEmpty)
            Positioned(
              bottom: 0,
              left: isMine ? 12 : null,
              right: isMine ? null : 12,
              child: ReactionPill(emoji: message.reactionEmoji),
            ),
        ],
      ),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      color: widget.highlighted
          ? theme.colorScheme.primary.withValues(alpha: .14)
          : Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: _resetDrag,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            // Reply arrow revealed while swiping.
            Positioned(
              left: 12,
              child: Opacity(
                opacity: (_dragX / _replyThreshold).clamp(0.0, 1.0),
                child: Icon(
                  Icons.reply,
                  color: _armed
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            AnimatedContainer(
              duration: _dragX == 0
                  ? const Duration(milliseconds: 180)
                  : Duration.zero,
              transform: Matrix4.translationValues(_dragX, 0, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: Row(
                mainAxisAlignment: isMine
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (message.pinned && isMine) const _PinMark(),
                  Flexible(
                    child: GestureDetector(
                      onLongPress: widget.onLongPress,
                      onDoubleTap: widget.onDoubleTap,
                      child: bubble,
                    ),
                  ),
                  if (message.pinned && !isMine) const _PinMark(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinMark extends StatelessWidget {
  const _PinMark();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Icon(
        Icons.push_pin,
        size: 14,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
