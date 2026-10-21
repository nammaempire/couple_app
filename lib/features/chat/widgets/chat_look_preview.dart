import 'package:flutter/material.dart';

import 'package:couple_app/features/chat/models/chat_look.dart';
import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/widgets/chat_background_layer.dart';
import 'package:couple_app/features/chat/widgets/chat_date_divider.dart';
import 'package:couple_app/features/chat/widgets/chat_palette.dart';
import 'package:couple_app/features/chat/widgets/message_bubble.dart';

/// A small, non-interactive chat drawn with the real background layer and
/// bubbles in [look], so the appearance screen shows exactly what the chat
/// will look like.
class ChatLookPreview extends StatelessWidget {
  const ChatLookPreview({
    super.key,
    required this.look,
    required this.partnerName,
    this.height = 300,
  });

  final ChatLook look;
  final String partnerName;
  final double height;

  static const _me = '_preview_me';
  static const _partner = '_preview_partner';

  List<Message> _messages() {
    final now = DateTime.now();
    DateTime at(int h, int m) => DateTime(now.year, now.month, now.day, h, m);
    final fromPartner = Message(
      id: 'p1',
      senderId: _partner,
      type: MessageType.text,
      text: 'Dinner at 8? I’ll bring dessert 🍰',
      sentAt: at(19, 42),
    );
    return [
      fromPartner,
      Message(
        id: 'm1',
        senderId: _me,
        type: MessageType.text,
        text: 'Yes please! Can’t wait 💕',
        sentAt: at(19, 44),
        seen: true,
        replyTo: ReplyPreview.of(fromPartner),
      ),
      Message(
        id: 'm2',
        senderId: _me,
        type: MessageType.text,
        text: 'Wearing the dress you like 😉',
        sentAt: at(19, 45),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChatPalette.applyTo(Theme.of(context), look);
    final messages = _messages();

    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Semantics(
            label: 'Preview of the chat',
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: SizedBox(
                    height: height,
                    child: Column(
                      children: [
                        _PreviewHeader(name: partnerName),
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: ChatBackgroundLayer(
                                  background: look.background,
                                ),
                              ),
                              SingleChildScrollView(
                                reverse: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Column(
                                  children: [
                                    ChatDateDivider(date: messages[0].sentAt),
                                    for (final m in messages)
                                      MessageBubble(
                                        message: m,
                                        isMine: m.senderId == _me,
                                        myUid: _me,
                                        partnerName: partnerName,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: scheme.outlineVariant),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = ChatPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: ChatPalette.diagonal(palette.headerGradient),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: ChatPalette.diagonal(palette.accentGradient),
              ),
              child: CircleAvatar(
                radius: 13,
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  name.isEmpty ? '♥' : name.characters.first.toUpperCase(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Icon(Icons.call_outlined, size: 18, color: scheme.onSurface),
            const SizedBox(width: 14),
            Icon(Icons.videocam_outlined, size: 18, color: scheme.onSurface),
          ],
        ),
      ),
    );
  }
}
