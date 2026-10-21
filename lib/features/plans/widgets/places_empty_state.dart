import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/plans/models/place.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';

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
    final (emoji, preset, title, hint) = filtering
        ? (
            '🔍',
            GradientPreset.lavender,
            'Nothing matches',
            'Try another category or show all places.',
          )
        : switch (status) {
            PlaceStatus.wantToGo => (
              '🧭',
              GradientPreset.mint,
              'Where to next?',
              'Save the cafés, trails and getaways you and $partnerName keep '
                  'talking about.',
            ),
            PlaceStatus.been => (
              '🗺️',
              GradientPreset.gold,
              'Your map of us starts here',
              'When you visit a place, mark it as been to keep a rating and '
                  'a note.',
            ),
          };

    final pill = FilledButton.styleFrom(
      minimumSize: const Size(0, 48),
      shape: const StadiumBorder(),
    );
    return GradientEmptyState(
      emoji: emoji,
      preset: preset,
      title: title,
      text: hint,
      action: filtering
          ? OutlinedButton(
              onPressed: onClearFilters,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                shape: const StadiumBorder(),
              ),
              child: const Text('Show all places'),
            )
          : status == PlaceStatus.wantToGo
          ? FilledButton.icon(
              onPressed: onAdd,
              style: pill,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Add a place'),
            )
          : null,
    );
  }
}
