import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';

import 'package:couple_app/features/music/models/song.dart';
import 'package:couple_app/features/music/widgets/moment_look.dart';
import 'package:couple_app/features/music/widgets/on_gradient_theme.dart';
import 'package:couple_app/features/music/widgets/song_artwork.dart';
import 'package:couple_app/features/music/widgets/song_tile.dart';

/// A saved video: a big 16:9 thumbnail with a "watch together" button,
/// then title, channel, moment and your heart.
class VideoCard extends StatelessWidget {
  const VideoCard({
    super.key,
    required this.video,
    required this.myUid,
    required this.partnerUid,
    required this.onTap,
    required this.onToggleLove,
    required this.onWatch,
    this.isPlaying = false,
  });

  final Song video;
  final String myUid;
  final String? partnerUid;
  final VoidCallback onTap;
  final VoidCallback onToggleLove;
  final VoidCallback onWatch;

  /// The video you're watching together right now.
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preset = video.moment.preset;
    final muted = preset.foregroundMuted(theme.brightness);
    final mine = video.isLovedBy(myUid);
    final both = video.lovedByBoth(myUid, partnerUid);
    final channel = video.artist.trim();
    final placeholder = SongArtworkPlaceholder(
      source: video.source,
      iconSize: 48,
    );
    final thumb = video.thumbnailUrl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: AnimatedGradientCard(
        preset: preset,
        onTap: onTap,
        radius: 22,
        animate: isPlaying,
        sheen: isPlaying,
        shadow: isPlaying,
        glow: isPlaying ? preset.accent(theme.brightness) : null,
        padding: EdgeInsets.zero,
        child: OnGradientTheme(
          preset: preset,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                // The thumbnail keeps the app's own colours.
                child: Theme(
                  data: theme,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (thumb.startsWith('https://'))
                        CachedNetworkImage(
                          imageUrl: thumb,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => placeholder,
                          errorWidget: (_, _, _) => placeholder,
                        )
                      else
                        placeholder,
                      Positioned(
                        left: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            isPlaying
                                ? '${video.moment.emoji} Watching now'
                                : '${video.moment.emoji} ${video.moment.label}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: IconButton.filled(
                          tooltip: 'Watch together',
                          onPressed: onWatch,
                          iconSize: 30,
                          icon: const Icon(Icons.play_arrow_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: preset.foreground(theme.brightness),
                            ),
                          ),
                          if (channel.isNotEmpty)
                            Text(
                              channel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: mine ? 'Remove your love' : 'Love it',
                      onPressed: onToggleLove,
                      icon: SongLoveIcon(mine: mine, both: both),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
