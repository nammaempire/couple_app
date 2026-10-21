import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/plans/models/place.dart';
import 'package:couple_app/features/plans/widgets/place_card.dart';
import 'package:couple_app/features/plans/widgets/place_rating_stars.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';

/// What the place details sheet asks the screen to do.
enum PlaceAction { openMaps, planDate, markBeen, markWantToGo, edit, delete }

/// Bottom sheet with a place's details and actions. Pops with a
/// [PlaceAction].
class PlaceDetailsSheet extends StatelessWidget {
  const PlaceDetailsSheet({
    super.key,
    required this.place,
    required this.addedBy,
  });

  final Place place;

  /// "you" or the partner's name.
  final String addedBy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visited = place.visitedAt;
    void pop(PlaceAction a) => Navigator.pop(context, a);

    Widget row(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );

    final preset = PlaceLook.presetFor(place.category);
    final fg = preset.foreground(theme.brightness);
    final fgMuted = preset.foregroundMuted(theme.brightness);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetGradientHeader(
              preset: PlaceLook.presetFor(place.category),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${place.category.emoji}  '
                          '${place.name.isEmpty ? 'Unnamed place' : place.name}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: fg,
                          ),
                        ),
                      ),
                      if (place.favourite)
                        Icon(Icons.favorite, color: scheme.primary, size: 20),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${place.category.label} · ${place.status.label} · '
                    'added by $addedBy',
                    style: theme.textTheme.bodySmall?.copyWith(color: fgMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (place.area.trim().isNotEmpty)
              row(Icons.place_outlined, place.area.trim()),
            if (place.isBeen && visited != null)
              row(
                Icons.event_available_outlined,
                'You went on ${DateFormat.yMMMMd().format(visited)}',
              ),
            if (place.isBeen && place.rating != null)
              Padding(
                padding: const EdgeInsets.only(left: 32, bottom: 10),
                child: PlaceRatingStars(rating: place.rating, size: 22),
              ),
            if (place.notes.trim().isNotEmpty)
              row(Icons.notes, place.notes.trim()),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => pop(PlaceAction.openMaps),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Open in Maps'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => pop(PlaceAction.planDate),
                    icon: const Icon(Icons.favorite_outline),
                    label: const Text('Plan a date here'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (place.isBeen)
                  TextButton.icon(
                    onPressed: () => pop(PlaceAction.markWantToGo),
                    icon: const Icon(Icons.bookmark_border),
                    label: const Text('Move to want to go'),
                  )
                else
                  TextButton.icon(
                    onPressed: () => pop(PlaceAction.markBeen),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('We\'ve been'),
                  ),
                TextButton.icon(
                  onPressed: () => pop(PlaceAction.edit),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed: () => pop(PlaceAction.delete),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
