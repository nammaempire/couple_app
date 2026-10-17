import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/together/models/love_note.dart';

/// What the recipient sees before a scheduled note arrives: when it opens
/// and how long to go.
class SealedNoteView extends StatelessWidget {
  const SealedNoteView({
    super.key,
    required this.note,
    required this.partnerName,
  });

  final LoveNote note;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final days = DateTime(
      note.deliverAt.year,
      note.deliverAt.month,
      note.deliverAt.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔒💌', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              'Sealed until ${DateFormat.MMMMd().add_jm().format(note.deliverAt)}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              days <= 0
                  ? '$partnerName wrote you something. It opens later today.'
                  : days == 1
                  ? '$partnerName wrote you something. It opens tomorrow.'
                  : '$partnerName wrote you something. $days days to go.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
