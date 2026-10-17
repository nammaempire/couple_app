import 'package:flutter/material.dart';

import 'package:couple_app/features/plans/models/place.dart';

/// Friendly empty state for a places tab, or for filters with no match.
class PlacesEmptyState extends StatelessWidget {
  const PlacesEmptyState({
    super.key,
    required this.status,
    required this.filtering,
    required this.partnerName,
    required this.onAdd,
    required this.onClearFilters,
  });

  final PlaceStatus status;
  final bool filtering;
  final String partnerName;
  final VoidCallback onAdd;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, title, hint) = filtering
        ? (
            Icons.filter_alt_off_outlined,
            'Nothing matches',
            'Try another category or show all places.',
          )
        : switch (status) {
            PlaceStatus.wantToGo => (
              Icons.explore_outlined,
              'Where to next?',
              'Save the cafés, trails and getaways you and $partnerName keep '
                  'talking about.',
            ),
            PlaceStatus.been => (
              Icons.map_outlined,
              'Your map of us starts here',
              'When you visit a place, mark it as been to keep a rating and '
                  'a note.',
            ),
          };

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: .6),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          if (filtering)
            OutlinedButton(
              onPressed: onClearFilters,
              child: const Text('Show all places'),
            )
          else if (status == PlaceStatus.wantToGo)
            FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Add a place'),
            ),
        ],
      ),
    );
  }
}
