import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';

import 'package:couple_app/features/music/data/media_shelf.dart';
import 'package:couple_app/features/music/models/song.dart';
import 'package:couple_app/features/music/widgets/moment_look.dart';
import 'package:couple_app/features/music/widgets/on_gradient_theme.dart';
import 'package:couple_app/features/music/widgets/song_artwork.dart';
import 'package:couple_app/features/music/widgets/song_source_style.dart';

/// What the song details sheet asks the screen to do.
enum SongAction { listenTogether, open, edit, delete }

/// Bottom sheet with a song's details and actions. Pops with a
/// [SongAction].
class SongDetailsSheet extends StatelessWidget {
  const SongDetailsSheet({
    super.key,
    required this.song,
    required this.addedBy,
    this.shelf = MediaShelf.songs,
  });

  final Song song;
  final MediaShelf shelf;

  /// "You" or the partner's name.
  final String addedBy;

  /// "played 3 times", "played once", "not played yet".
  static String playsText(int n) => switch (n) {
    0 => 'not played yet',
    1 => 'played once',
    _ => 'played $n times',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final note = song.note.trim();
    final preset = song.moment.preset;
    final particles = song.moment.particles;
    void pop(SongAction a) => Navigator.pop(context, a);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedGradientCard(
              preset: preset,
              radius: 28,
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: OnGradientTheme(
                preset: preset,
                child: Stack(
                  children: [
                    if (particles != null)
                      Positioned.fill(
                        child: FloatingHearts(
                          style: particles,
                          count: 10,
                          opacity: .45,
                          color: song.moment.particleColor(theme.brightness),
                        ),
                      ),
                    Builder(builder: (context) => _header(context, theme)),
                  ],
                ),
              ),
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(16),
                  border: Border(
                    left: BorderSide(color: scheme.primary, width: 3),
                  ),
                ),
                child: Text(
                  '“$note”',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Added by $addedBy · ${playsText(song.playCount)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => pop(SongAction.listenTogether),
              icon: Icon(
                shelf == MediaShelf.videos
                    ? Icons.live_tv_outlined
                    : Icons.headphones_outlined,
              ),
              label: Text(shelf.together),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => pop(SongAction.open),
              icon: Icon(song.source.icon),
              label: Text('Open in ${song.source.label}'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () => pop(SongAction.edit),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => pop(SongAction.delete),
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

  Widget _header(BuildContext context, ThemeData outer) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final artist = song.artist.trim();
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Theme(
              data: outer,
              child: SongArtwork(
                url: song.thumbnailUrl,
                source: song.source,
                size: song.playsInApp ? 260 : 156,
                aspectRatio: song.playsInApp ? 16 / 9 : 1,
                radius: 20,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            song.displayTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (artist.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              artist,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              SongSourceBadge(source: song.source, dense: false),
              Text(
                '${song.moment.emoji} ${song.moment.label}',
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
