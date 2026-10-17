import 'package:flutter/material.dart';

/// Shown when there are no memories yet, or none match the filters.
class MemoriesEmptyState extends StatelessWidget {
  const MemoriesEmptyState({
    super.key,
    required this.filtering,
    required this.onCreate,
  });

  final bool filtering;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            filtering ? Icons.search_off : Icons.photo_album_outlined,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            filtering ? 'No memories match' : 'Your story starts here',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            filtering
                ? 'Try another album, date or search.'
                : 'Add your first memory: a first date, a trip, or any '
                      'moment worth keeping.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (!filtering) ...[
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Add a memory'),
            ),
          ],
        ],
      ),
    );
  }
}
