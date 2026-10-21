import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/plans/models/place.dart';
import 'package:couple_app/features/plans/widgets/place_rating_stars.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';

/// A saved place: category, name, area, and for places you've been, the
/// rating and visit date. Quick favourite and maps buttons on the right.
class PlaceCard extends StatelessWidget {
  const PlaceCard({
    super.key,
    required this.place,
    required this.onTap,
    required this.onToggleFavourite,
    required this.onOpenMaps,
  });

  final Place place;
  final VoidCallback onTap;
  final VoidCallback onToggleFavourite;
  final VoidCallback onOpenMaps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visited = place.visitedAt;
    final area = place.area.trim();
    final notes = place.notes.trim();

    final preset = PlaceLook.presetFor(place.category);
    return TintedCard(
      preset: preset,
      onTap: onTap,
      edge: place.isBeen,
      radius: 22,
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EmojiBadge(emoji: place.category.emoji, preset: preset, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name.isEmpty ? 'Unnamed place' : place.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    area.isEmpty
                        ? place.category.label
                        : '${place.category.label} · $area',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (place.isBeen &&
                      (place.rating != null || visited != null)) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (place.rating != null) ...[
                          PlaceRatingStars(rating: place.rating),
                          const SizedBox(width: 8),
                        ],
                        if (visited != null)
                          Flexible(
                            child: Text(
                              'Went ${DateFormat.yMMMd().format(visited)}',
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      notes,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: place.favourite
                    ? 'Remove from favourites'
                    : 'Add to favourites',
                onPressed: onToggleFavourite,
                icon: Icon(
                  place.favourite ? Icons.favorite : Icons.favorite_border,
                  color: place.favourite
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
              ),
              IconButton(
                tooltip: 'Open in Maps',
                onPressed: onOpenMaps,
                icon: Icon(Icons.map_outlined, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The gradient each kind of place wears.
abstract final class PlaceLook {
  static GradientPreset presetFor(PlaceCategory c) => switch (c) {
    PlaceCategory.restaurant => GradientPreset.sunset,
    PlaceCategory.cafe => GradientPreset.peach,
    PlaceCategory.bar => GradientPreset.lavender,
    PlaceCategory.outdoors => GradientPreset.mint,
    PlaceCategory.travel => GradientPreset.ocean,
    PlaceCategory.shopping => GradientPreset.blush,
    PlaceCategory.activity => GradientPreset.festive,
    PlaceCategory.other => GradientPreset.sunny,
  };
}
