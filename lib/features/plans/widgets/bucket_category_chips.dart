import 'package:flutter/material.dart';

import 'package:couple_app/features/plans/models/bucket_item.dart';

/// A horizontal row of filter chips: all, then each category in use.
class BucketCategoryChips extends StatelessWidget {
  const BucketCategoryChips({
    super.key,
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  /// Null means "All".
  final BucketCategory? selected;
  final Map<BucketCategory, int> counts;
  final ValueChanged<BucketCategory?> onSelected;

  @override
  Widget build(BuildContext context) {
    // Show categories that have items, plus the selected one so it can be
    // cleared even after its last item is deleted.
    final shown = [
      for (final c in BucketCategory.values)
        if ((counts[c] ?? 0) > 0 || c == selected) c,
    ];

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All'),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final c in shown)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${c.emoji} ${c.label} · ${counts[c] ?? 0}'),
                selected: selected == c,
                onSelected: (_) => onSelected(selected == c ? null : c),
              ),
            ),
        ],
      ),
    );
  }
}
