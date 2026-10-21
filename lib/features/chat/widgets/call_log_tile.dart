import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/utils/duration_format.dart';
import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/widgets/chat_chrome.dart';
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
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 5, 14, 5),
          decoration: BoxDecoration(
            color: ChatPalette.of(context).systemChip,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ChatPalette.of(context).glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GradientBadge(
                icon: icon,
                size: 24,
                iconSize: 14,
                colors: alert
                    ? [
                        theme.colorScheme.error,
                        Color.lerp(
                          theme.colorScheme.error,
                          theme.colorScheme.tertiary,
                          .35,
                        )!,
                      ]
                    : null,
                foreground: alert ? theme.colorScheme.onError : null,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$label$time',
                  style: theme.textTheme.labelMedium?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
