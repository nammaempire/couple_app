import 'package:flutter/material.dart';

import 'package:couple_app/features/chat/models/message.dart';

/// Bottom sheet for a long-pressed message: a row of reactions, then reply,
/// copy, pin and delete.
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

  @override
  Widget build(BuildContext context) {
    final isMine = message.senderId == myUid;
    final theme = Theme.of(context);

    void run(VoidCallback action) {
      Navigator.pop(context);
      action();
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: CoupleReaction.values.map((reaction) {
                final isActive = message.reactions[myUid] == reaction.emoji;
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => run(() => onReact(reaction.emoji)),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive
                                ? theme.colorScheme.primary.withValues(
                                    alpha: .18,
                                  )
                                : Colors.transparent,
                          ),
                          child: Text(
                            reaction.emoji,
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                        Text(reaction.label, style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.reply),
            title: const Text('Reply'),
            onTap: () => run(onReply),
          ),
          if (message.type == MessageType.text ||
              (message.type == MessageType.sticker && message.text.isNotEmpty))
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(
                message.type == MessageType.sticker
                    ? 'Copy quote'
                    : 'Copy text',
              ),
              onTap: () => run(onCopy),
            ),
          ListTile(
            leading: Icon(
              message.pinned ? Icons.push_pin_outlined : Icons.push_pin,
            ),
            title: Text(message.pinned ? 'Unpin' : 'Pin'),
            onTap: () => run(onTogglePin),
          ),
          if (isMine)
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
              ),
              title: Text(
                'Delete for both of you',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: () => run(onDelete),
            ),
        ],
      ),
    );
  }
}
