import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/utils/duration_format.dart';
import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/widgets/chat_palette.dart';

/// A call record, shown centred in the conversation rather than as a bubble.
class CallLogTile extends StatelessWidget {
  const CallLogTile({super.key, required this.message, required this.myUid});

  final Message message;
  final String myUid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iCalled = message.senderId == myUid;
    final kind = message.isVideoCall ? 'video call' : 'voice call';
    final outcome = message.callOutcome ?? CallOutcome.missed;
    final duration = message.duration;

    final (IconData icon, String label, bool alert) = switch (outcome) {
      CallOutcome.completed => (
        message.isVideoCall ? Icons.videocam : Icons.call,
        '${iCalled ? 'Outgoing' : 'Incoming'} $kind'
            '${duration == null ? '' : ' (${formatDuration(duration)})'}',
        false,
      ),
      CallOutcome.missed => (
        iCalled ? Icons.call_made : Icons.call_missed,
        iCalled ? 'No answer · $kind' : 'Missed $kind',
        !iCalled,
      ),
      CallOutcome.declined => (
        Icons.call_end,
        iCalled ? 'Declined · $kind' : 'You declined a $kind',
        false,
      ),
    };

    final time = message.sentAt == null
        ? ''
        : ' · ${DateFormat.jm().format(message.sentAt!)}';
    final color = alert
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: ChatPalette.of(context).systemChip,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                '$label$time',
                style: theme.textTheme.labelMedium?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
