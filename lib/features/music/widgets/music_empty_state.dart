import 'package:flutter/material.dart';

import 'package:couple_app/features/music/data/media_shelf.dart';

/// Friendly empty state for the music library, or for filters with no
/// match.
class MusicEmptyState extends StatelessWidget {
  const MusicEmptyState({
    super.key,
    this.shelf = MediaShelf.songs,
    required this.filtering,
    required this.onAdd,
    required this.onClearFilters,
  });

  final MediaShelf shelf;
  final bool filtering;
  final VoidCallback onAdd;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, title, hint) = filtering
        ? (
            Icons.search_off,
            'Nothing matches',
            'Try another search or show all your ${shelf.item}s.',
          )
        : shelf == MediaShelf.videos
        ? (
            Icons.smart_display_outlined,
            'Watch together — paste a YouTube link',
            'Movies, shows, vlogs, trailers: save them here and watch at the '
                'same moment, even when you’re apart.',
          )
        : (
            Icons.library_music_outlined,
            'Your songs, together',
            'Paste a link from Spotify, YouTube, YouTube Music, Apple Music '
                'or JioSaavn. Then listen at the same time, even when you’re '
                'apart.',
          );

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
              child: Text('Show all ${shelf.item}s'),
            )
          else
            FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text('Add your first ${shelf.item}'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            ),
        ],
      ),
    );
  }
}
