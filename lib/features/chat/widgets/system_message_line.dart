import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/widgets/chat_palette.dart';

/// A system message (chat cleared, screenshot taken, screenshot blocking
/// switched), shown as a small centred line rather than a bubble.
///
/// System lines can't be replied to, reacted to or pinned; the sender can
/// long-press to delete theirs.
class SystemMessageLine extends StatelessWidget {
  const SystemMessageLine({
    super.key,
    required this.message,
    required this.myUid,
    required this.partnerName,
    this.onLongPress,
  });

  final Message message;
  final String myUid;
  final String partnerName;

  /// Only given for my own lines.
  final VoidCallback? onLongPress;

  /// The wording for this phone: "You …" for my lines, the partner's name
  /// for theirs.
  static String labelFor(
    Message message, {
    required String myUid,
    required String partnerName,
  }) {
    final mine = message.senderId == myUid;
    final who = mine ? 'You' : partnerName;
    switch (message.type) {
      case MessageType.chatCleared:
        return '🧹 $who cleared the chat';
      case MessageType.screenshot:
        final of = switch (message.screenshotOf) {
          ScreenshotSubject.photo => ' of a photo',
          ScreenshotSubject.video => ' of a video',
          ScreenshotSubject.chat => mine ? '' : ' of the chat',
        };
        return '📸 $who took a screenshot$of';
      case MessageType.screenshotBlock:
        final state = message.screenshotsBlocked ? 'on' : 'off';
        return '🔒 $who turned $state screenshot blocking';
      case MessageType.text:
      case MessageType.image:
      case MessageType.video:
      case MessageType.voice:
      case MessageType.call:
      case MessageType.sticker:
        return message.previewText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final time = message.sentAt == null
        ? ''
        : ' · ${DateFormat.jm().format(message.sentAt!)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
      child: Center(
        child: GestureDetector(
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: ChatPalette.of(context).systemChip,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ChatPalette.of(context).glassBorder),
            ),
            child: Text(
              '${labelFor(message, myUid: myUid, partnerName: partnerName)}'
              '$time',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(color: color),
            ),
          ),
        ),
      ),
    );
  }
}
