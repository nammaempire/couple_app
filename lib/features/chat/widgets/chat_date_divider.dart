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
    final scheme = theme.colorScheme;

    Widget line(bool leading) => Expanded(
      child: Container(
        height: 1,
        margin: EdgeInsets.only(
          left: leading ? 32 : 10,
          right: leading ? 10 : 32,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primary.withValues(alpha: leading ? 0 : .28),
              scheme.primary.withValues(alpha: leading ? .28 : 0),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          // Over a photo or pattern, plain lines would get lost.
          if (!palette.hasBackground) line(true) else const Spacer(),
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.systemChip,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.glassBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .4,
                ),
              ),
            ),
          ),
          if (!palette.hasBackground) line(false) else const Spacer(),
        ],
      ),
    );
  }
}
