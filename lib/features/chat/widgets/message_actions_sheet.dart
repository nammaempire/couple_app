import 'package:flutter/material.dart';

import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/widgets/chat_chrome.dart';
import 'package:couple_app/features/chat/widgets/chat_palette.dart';

/// Bottom sheet for a long-pressed message: a row of reactions, then reply,
/// copy, pin and delete. System lines only offer delete, to their sender.
///
/// Each choice closes the sheet before its callback runs.
class MessageActionsSheet extends StatelessWidget {
  const MessageActionsSheet({
    super.key,
    required this.message,
    required this.myUid,
    required this.onReact,
    required this.onReply,
    required this.onCopy,
    required this.onTogglePin,
    required this.onDelete,
    this.allowCopy = true,
  });

  final Message message;
  final String myUid;

  /// Called with the chosen reaction's emoji.
  final ValueChanged<String> onReact;
  final VoidCallback onReply;

  /// Only offered for text messages and sticker quotes.
  final VoidCallback onCopy;
  final VoidCallback onTogglePin;

  /// Only offered for my own messages.
  final VoidCallback onDelete;

  /// Whether text may be copied out of the app (not while the pairing is
  /// ending).
  final bool allowCopy;

  @override
  Widget build(BuildContext context) {
    final isMine = message.senderId == myUid;
    final interactive = !message.isSystem;
    final theme = Theme.of(context);

    void run(VoidCallback action) {
      Navigator.pop(context);
      action();
    }

    final palette = ChatPalette.of(context);
    final dark = theme.brightness == Brightness.dark;

    return SafeArea(
      // Scrolls rather than overflowing with large text.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ChatSheetHeader(),
            if (interactive) ...[
              // The reactions sit in a glassy gradient-edged strip.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: dark
                        ? Colors.white.withValues(alpha: .06)
                        : Colors.white.withValues(alpha: .72),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: dark ? .08 : .9),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: palette.glow.withValues(alpha: .12),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: CoupleReaction.values.map((reaction) {
                      final isActive =
                          message.reactions[myUid] == reaction.emoji;
                      return Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => run(() => onReact(reaction.emoji)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Column(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: isActive
                                        ? ChatPalette.diagonal([
                                            for (final c
                                                in palette.accentGradient)
                                              c.withValues(alpha: .28),
                                          ])
                                        : null,
                                  ),
                                  child: FittedBox(
                                    child: Text(
                                      reaction.emoji,
                                      style: const TextStyle(fontSize: 28),
                                    ),
                                  ),
                                ),
                                Text(
                                  reaction.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              ChatSheetOption(
                icon: Icons.reply,
                title: 'Reply',
                onTap: () => run(onReply),
              ),
            ],
            if (allowCopy &&
                (message.type == MessageType.text ||
                    (message.type == MessageType.sticker &&
                        message.text.isNotEmpty)))
              ChatSheetOption(
                icon: Icons.copy,
                title: message.type == MessageType.sticker
                    ? 'Copy quote'
                    : 'Copy text',
                onTap: () => run(onCopy),
              ),
            if (interactive)
              ChatSheetOption(
                icon: message.pinned ? Icons.push_pin_outlined : Icons.push_pin,
                title: message.pinned ? 'Unpin' : 'Pin',
                onTap: () => run(onTogglePin),
              ),
            if (isMine)
              ChatSheetOption(
                icon: Icons.delete_outline,
                title: message.isSystem ? 'Delete' : 'Delete for both of you',
                destructive: true,
                onTap: () => run(onDelete),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
