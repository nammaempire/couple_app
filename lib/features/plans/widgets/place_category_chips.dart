import 'package:flutter/material.dart';

import 'package:couple_app/features/plans/models/place.dart';

/// A horizontal row of category filters, "All" first. Only categories in
/// [categories] are shown.
class PlaceCategoryChips extends StatelessWidget {
  const PlaceCategoryChips({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<PlaceCategory> categories;
  final PlaceCategory? selected;
  final ValueChanged<PlaceCategory?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          FilterChip(
            label: const Text('All'),
            selected: selected == null,
            showCheckmark: false,
            onSelected: (_) => onSelected(null),
          ),
          for (final c in categories)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: FilterChip(
                label: Text('${c.emoji} ${c.label}'),
                selected: selected == c,
                showCheckmark: false,
                onSelected: (on) => onSelected(on ? c : null),
              ),
            ),
        ],
      ),
    );
  }
}
