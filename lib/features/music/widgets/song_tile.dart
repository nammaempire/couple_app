import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';

import 'package:couple_app/features/music/models/song.dart';
import 'package:couple_app/features/music/widgets/moment_look.dart';
import 'package:couple_app/features/music/widgets/on_gradient_theme.dart';
import 'package:couple_app/features/music/widgets/song_artwork.dart';
import 'package:couple_app/features/music/widgets/song_source_style.dart';

/// A song in the library: artwork, title, artist, where it plays and what
/// it means to you, with a heart for your love and a "listen together"
/// button.
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.myUid,
    required this.partnerUid,
    required this.onTap,
    required this.onToggleLove,
    required this.onListen,
    this.isPlaying = false,
  });

  final Song song;
  final String myUid;
  final String? partnerUid;
  final VoidCallback onTap;
  final VoidCallback onToggleLove;
  final VoidCallback onListen;

  /// The song you're listening to together right now.
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = song.isLovedBy(myUid);
    final both = song.lovedByBoth(myUid, partnerUid);
    final artist = song.artist.trim();

    final preset = song.moment.preset;
    final outer = theme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: AnimatedGradientCard(
        preset: preset,
        onTap: onTap,
        radius: 20,
        animate: isPlaying,
        sheen: isPlaying,
        shadow: isPlaying,
        glow: isPlaying ? preset.accent(theme.brightness) : null,
        padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
        child: OnGradientTheme(
          preset: preset,
          child: Builder(
            builder: (context) {
              final theme = Theme.of(context);
              final scheme = theme.colorScheme;
              return Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .12),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    // The artwork keeps the app's own colours.
                    child: Theme(
                      data: outer,
                      child: SongArtwork(
                        url: song.thumbnailUrl,
                        source: song.source,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (artist.isNotEmpty)
                          Text(
                            artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Flexible(
                              child: SongSourceBadge(source: song.source),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              song.moment.emoji,
                              semanticsLabel: song.moment.label,
                              style: const TextStyle(fontSize: 13),
                            ),
                            if (isPlaying) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Playing now',
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: mine ? 'Remove your love' : 'Love it',
                    onPressed: onToggleLove,
                    icon: SongLoveIcon(mine: mine, both: both),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Listen together',
                    onPressed: onListen,
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                  const SizedBox(width: 4),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A heart: outlined, filled when you love it, doubled when you both do.
class SongLoveIcon extends StatelessWidget {
  const SongLoveIcon({
    super.key,
    required this.mine,
    required this.both,
    this.size = 24,
  });

  final bool mine;
  final bool both;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!both) {
      return Icon(
        mine ? Icons.favorite : Icons.favorite_border,
        size: size,
        color: mine ? scheme.primary : scheme.onSurfaceVariant,
      );
    }
    // Two overlapping hearts: you both love it.
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -size * .18,
            top: -size * .08,
            child: Icon(
              Icons.favorite,
              size: size * .78,
              color: scheme.primary.withValues(alpha: .55),
            ),
          ),
          Positioned(
            right: -size * .12,
            bottom: -size * .06,
            child: Icon(
              Icons.favorite,
              size: size * .84,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
