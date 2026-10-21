import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';

import 'package:couple_app/features/music/models/song_link.dart';
import 'package:couple_app/features/music/widgets/on_gradient_theme.dart';
import 'package:couple_app/features/music/widgets/song_artwork.dart';
import 'package:couple_app/features/music/widgets/song_source_style.dart';

/// How a song link will look and play, shown in the editor.
class SongLinkPreview extends StatelessWidget {
  const SongLinkPreview({
    super.key,
    required this.source,
    required this.playsInApp,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    this.loading = false,
    this.preset = GradientPreset.blush,
  });

  /// The card's gradient (the chosen moment's).
  final GradientPreset preset;

  final SongSource source;
  final bool playsInApp;
  final String title;
  final String artist;
  final String thumbnailUrl;

  /// Looking the link up: show a small spinner.
  final bool loading;

  /// What listening together will do with this link.
  static String howItPlays(SongSource source, {required bool playsInApp}) =>
      playsInApp
      ? 'Plays inside the app, in sync'
      : 'Opens in ${source.label} on both phones at the same moment';

  @override
  Widget build(BuildContext context) {
    final outer = Theme.of(context);
    final shownTitle = title.trim().isEmpty
        ? '${source.label} link'
        : title.trim();

    return AnimatedGradientCard(
      preset: preset,
      padding: const EdgeInsets.all(12),
      radius: 20,
      child: OnGradientTheme(
        preset: preset,
        child: Builder(
          builder: (context) {
            final theme = Theme.of(context);
            final scheme = theme.colorScheme;
            return Row(
              children: [
                Theme(
                  data: outer,
                  child: SongArtwork(
                    url: thumbnailUrl,
                    source: source,
                    size: playsInApp ? 96 : 64,
                    aspectRatio: playsInApp ? 16 / 9 : 1,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SongSourceBadge(source: source),
                          if (loading) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        shownTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (artist.trim().isNotEmpty)
                        Text(
                          artist.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            playsInApp ? Icons.sync : Icons.open_in_new,
                            size: 14,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              howItPlays(source, playsInApp: playsInApp),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
