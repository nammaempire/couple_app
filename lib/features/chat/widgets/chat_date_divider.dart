import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/chat/widgets/chat_palette.dart';

/// "Today" or the date, between messages sent on different days.
class ChatDateDivider extends StatelessWidget {
  const ChatDateDivider({super.key, required this.date});

  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    if (date == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final isToday =
        date!.year == now.year &&
        date!.month == now.month &&
        date!.day == now.day;
    final label = isToday ? 'Today' : DateFormat.yMMMd().format(date!);

    final theme = Theme.of(context);
    final palette = ChatPalette.of(context);
    final text = Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: palette.hasBackground ? 8 : 12),
      // Over a photo or pattern the label gets a pill to stay readable.
      child: palette.hasBackground
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: palette.systemChip,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: text,
              ),
            )
          : text,
    );
  }
}
