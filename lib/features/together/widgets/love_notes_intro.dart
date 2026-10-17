import 'package:flutter/material.dart';

import 'package:couple_app/features/together/models/love_note.dart';
import 'package:couple_app/features/together/widgets/open_when_template_row.dart';

/// Welcome card shown before any notes exist, with "Open when…" templates.
class LoveNotesIntro extends StatelessWidget {
  const LoveNotesIntro({
    super.key,
    required this.partnerName,
    required this.onTemplate,
  });

  final String partnerName;
  final ValueChanged<OpenWhen> onTemplate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: .6),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('💌', style: TextStyle(fontSize: 36)),
              const SizedBox(height: 8),
              Text(
                'Leave $partnerName a love note',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Send it now, schedule it for a special day, or leave an '
                '“Open when…” envelope for when they need it. Scheduled '
                'notes stay sealed until they arrive.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        OpenWhenTemplateRow(onTemplate: onTemplate),
      ],
    );
  }
}
