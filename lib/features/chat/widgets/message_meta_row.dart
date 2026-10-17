import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/chat/models/message.dart';

/// Send time and, for my messages, the sent / delivered / seen tick.
class MessageMetaRow extends StatelessWidget {
  const MessageMetaRow({
    super.key,
    required this.message,
    required this.isMine,
    required this.color,
  });

  final Message message;
  final bool isMine;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final sentAt = message.sentAt;
    final label = sentAt == null ? '' : DateFormat.jm().format(sentAt);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: color)),
        if (isMine) ...[
          const SizedBox(width: 4),
          Icon(
            sentAt == null
                ? Icons.schedule
                : message.seen
                ? Icons.done_all
                : Icons.done,
            size: 14,
            color: color,
          ),
        ],
      ],
    );
  }
}
