import 'package:flutter/material.dart';

/// A warm banner at the top of the ideas list that picks a random idea.
class DatePlanSurpriseCard extends StatelessWidget {
  const DatePlanSurpriseCard({
    super.key,
    required this.ideaCount,
    required this.onSurprise,
  });

  final int ideaCount;
  final VoidCallback onSurprise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primaryContainer, scheme.tertiaryContainer],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Can\'t decide?',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ideaCount == 1
                        ? 'You have one idea waiting.'
                        : 'We\'ll pick one of your $ideaCount ideas.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onSurprise,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.casino_outlined),
              label: const Text('Surprise me'),
            ),
          ],
        ),
      ),
    );
  }
}
