import 'package:flutter/material.dart';

import 'package:couple_app/features/music/models/song_link.dart';

/// Colour and icon for each place a song link can point to.
extension SongSourceStyle on SongSource {
  Color get color => switch (this) {
    SongSource.spotify => const Color(0xFF1DB954),
    SongSource.youtube => const Color(0xFFE62117),
    SongSource.youtubeMusic => const Color(0xFFD9002A),
    SongSource.appleMusic => const Color(0xFFFA2D48),
    SongSource.jioSaavn => const Color(0xFF1FA99A),
    SongSource.soundCloud => const Color(0xFFFF5500),
    SongSource.other => const Color(0xFF7A6F73),
  };

  IconData get icon => switch (this) {
    SongSource.spotify => Icons.graphic_eq,
    SongSource.youtube => Icons.smart_display,
    SongSource.youtubeMusic => Icons.album,
    SongSource.appleMusic => Icons.music_note,
    SongSource.jioSaavn => Icons.queue_music,
    SongSource.soundCloud => Icons.cloud,
    SongSource.other => Icons.link,
  };
}

/// A small pill naming where a song plays: "YouTube", "Spotify"…
class SongSourceBadge extends StatelessWidget {
  const SongSourceBadge({super.key, required this.source, this.dense = true});

  final SongSource source;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    // The brand colour, deepened on light backgrounds and lifted on dark
    // ones so the label stays readable on any card gradient.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark
        ? Color.lerp(source.color, Colors.white, .5)!
        : Color.lerp(source.color, Colors.black, .35)!;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: color,
      fontWeight: FontWeight.w700,
      fontSize: dense ? 11 : 12,
    );
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: 2),
      decoration: BoxDecoration(
        color: dark
            ? Colors.black.withValues(alpha: .28)
            : Colors.white.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(source.icon, size: dense ? 12 : 14, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              source.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}
