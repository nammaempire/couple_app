import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/widgets/chat_chrome.dart';

/// Bottom sheet listing every pinned message.
///
/// Tapping a message closes the sheet with its id, so the chat can jump to
/// it.
class PinnedMessagesSheet extends StatelessWidget {
  const PinnedMessagesSheet({
    super.key,
    required this.pinnedStream,
    required this.nameFor,
    required this.onUnpin,
  });

  final Stream<List<Message>> pinnedStream;

  /// "You" or the partner's name for a sender uid.
  final String Function(String uid) nameFor;
  final ValueChanged<Message> onUnpin;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Message>>(
      stream: pinnedStream,
      builder: (builderContext, snapshot) {
        final pinned = snapshot.data ?? const <Message>[];
        final theme = Theme.of(builderContext);
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(builderContext).height * .7,
          ),
          child: pinned.isEmpty
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ChatSheetHeader(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                      child: Text(
                        'Nothing pinned yet. Long-press a message and choose '
                        'Pin to keep it here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    const ChatSheetHeader(
                      title: 'Pinned messages',
                      icon: Icons.push_pin,
                    ),
                    for (final m in pinned)
                      ChatSheetOption(
                        icon: Icons.push_pin_outlined,
                        title: m.previewText,
                        titleMaxLines: 2,
                        subtitle:
                            '${nameFor(m.senderId)}'
                            '${m.sentAt == null ? '' : ' · ${DateFormat.yMMMd().format(m.sentAt!)}'}',
                        trailing: IconButton(
                          tooltip: 'Unpin',
                          icon: const Icon(Icons.close),
                          onPressed: () => onUnpin(m),
                        ),
                        onTap: () => Navigator.pop(context, m.id),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
        );
      },
    );
  }
}
