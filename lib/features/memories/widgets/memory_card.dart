import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/memories/models/memory.dart';
import 'package:couple_app/features/memories/widgets/memory_count_badge.dart';
import 'package:couple_app/features/memories/widgets/memory_look.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';

/// A memory in the timeline. With a photo: a rounded cover with a gradient
/// scrim and the title on it. Without: a soft card in the album's gradient
/// with its emoji.
class MemoryCard extends StatelessWidget {
  const MemoryCard({
    super.key,
    required this.memory,
    required this.onTap,
    required this.onToggleFavourite,
  });

  final Memory memory;
  final VoidCallback onTap;
  final VoidCallback onToggleFavourite;

  String get _title => memory.title.isEmpty ? 'Untitled' : memory.title;

  String get _meta => [
    DateFormat.yMMMd().format(memory.date),
    if (memory.place != null) memory.place!,
    '${MemoryAlbums.emojiFor(memory.album)} ${memory.album}',
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final cover = memory.coverUrl;
    return cover == null ? _plain(context) : _photo(context, cover);
  }

  Widget _favourite(BuildContext context, {bool onPhoto = false}) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: memory.favorite ? 'Remove from favourites' : 'Add to favourites',
      style: onPhoto
          ? IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: .32),
            )
          : null,
      icon: Icon(
        memory.favorite ? Icons.favorite : Icons.favorite_border,
        color: onPhoto
            ? (memory.favorite ? const Color(0xFFFF8FB1) : Colors.white)
            : (memory.favorite ? scheme.primary : null),
      ),
      onPressed: onToggleFavourite,
    );
  }

  Widget _plain(BuildContext context) {
    final theme = Theme.of(context);
    final preset = MemoryLook.presetFor(memory.album);
    return TintedCard(
      preset: preset,
      onTap: onTap,
      radius: 22,
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EmojiBadge(
            emoji: MemoryAlbums.emojiFor(memory.album),
            preset: preset,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (memory.caption.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      memory.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ),
          _favourite(context),
        ],
      ),
    );
  }

  Widget _photo(BuildContext context, String cover) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final preset = MemoryLook.presetFor(memory.album);
    return TintedCard(
      preset: preset,
      onTap: onTap,
      radius: 24,
      strength: .55,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: cover,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: preset.colors(theme.brightness),
                        ),
                      ),
                    ),
                    errorWidget: (_, _, _) => Container(
                      color: scheme.surfaceContainerHighest,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                  // A soft scrim so the title reads on any photo.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, .3, .55, 1],
                        colors: [
                          Color(0x33000000),
                          Color(0x00000000),
                          Color(0x14000000),
                          Color(0xC2000000),
                        ],
                      ),
                    ),
                  ),
                  if (memory.media.length > 1)
                    Positioned(
                      left: 12,
                      top: 12,
                      child: MemoryCountBadge(memory: memory),
                    ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: _favourite(context, onPhoto: true),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: .9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (memory.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Text(
                memory.caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }
}
