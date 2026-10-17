import 'package:flutter/material.dart';

import 'package:couple_app/features/together/models/love_note.dart';

/// A delivered "Open when…" envelope waiting to be opened.
class NoteEnvelopeView extends StatelessWidget {
  const NoteEnvelopeView({super.key, required this.note, required this.onOpen});

  final LoveNote note;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(note.emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              note.envelopeTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Only open it when the moment is right.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.drafts_outlined),
              label: const Text('Open it'),
            ),
          ],
        ),
      ),
    );
  }
}
