import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:couple_app/features/music/models/song_link.dart';
import 'package:couple_app/features/music/widgets/song_source_style.dart';

/// A song's cover art, or a soft gradient with its source's icon when there
/// is none (or it fails to load).
class SongArtwork extends StatelessWidget {
  const SongArtwork({
    super.key,
    required this.url,
    required this.source,
    this.size = 56,
    this.radius = 14,
    this.aspectRatio = 1,
  });

  final String url;
  final SongSource source;

  /// Width; the height follows [aspectRatio].
  final double size;
  final double radius;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final fallback = SongArtworkPlaceholder(
      source: source,
      iconSize: size * .4,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size / aspectRatio,
        child: url.startsWith('https://')
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );
  }
}

/// The artwork stand-in: the app's rose blending into the source's colour.
class SongArtworkPlaceholder extends StatelessWidget {
  const SongArtworkPlaceholder({
    super.key,
    required this.source,
    this.iconSize = 24,
  });

  final SongSource source;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            Color.lerp(scheme.primary, source.color, .55)!,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          source.icon,
          size: iconSize,
          color: Colors.white.withValues(alpha: .9),
        ),
      ),
    );
  }
}
