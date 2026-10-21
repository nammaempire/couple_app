import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/memories/data/memory_service.dart';
import 'package:couple_app/features/memories/models/memory.dart';

/// Horizontal row of the memory's photos and videos, with an add tile.
class MemoryMediaStrip extends StatelessWidget {
  const MemoryMediaStrip({
    super.key,
    required this.kept,
    required this.added,
    required this.onAdd,
    required this.onRemoveKept,
    required this.onRemoveAdded,
  });

  final List<MemoryMedia> kept;
  final List<PendingMedia> added;
  final VoidCallback onAdd;
  final ValueChanged<MemoryMedia> onRemoveKept;
  final ValueChanged<PendingMedia> onRemoveAdded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const size = 104.0;

    Widget tile({
      required Widget child,
      required bool isVideo,
      required VoidCallback onRemove,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(width: size, height: size, child: child),
            ),
            if (isVideo)
              const Positioned(
                left: 6,
                bottom: 6,
                child: Icon(Icons.play_circle_fill, color: Colors.white),
              ),
            Positioned(
              right: 4,
              top: 4,
              child: InkWell(
                onTap: onRemove,
                customBorder: const CircleBorder(),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final videoPlaceholder = Container(
      color: const Color(0xFF2A2124),
      child: const Icon(Icons.videocam, color: Colors.white54),
    );

    return SizedBox(
      height: size,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final m in kept)
            tile(
              isVideo: m.isVideo,
              onRemove: () => onRemoveKept(m),
              child: m.previewUrl == null
                  ? videoPlaceholder
                  : CachedNetworkImage(
                      imageUrl: m.previewUrl!,
                      fit: BoxFit.cover,
                    ),
            ),
          for (final m in added)
            tile(
              isVideo: m.isVideo,
              onRemove: () => onRemoveAdded(m),
              child: m.isVideo
                  ? videoPlaceholder
                  : Image.file(m.file, fit: BoxFit.cover),
            ),
          InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    GradientPreset.sunset.accent(theme.brightness),
                    GradientPreset.festive.accent(theme.brightness),
                  ],
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16.5),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: GradientPreset.sunset.colors(theme.brightness),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      color: GradientPreset.sunset.accent(theme.brightness),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add photos\nor videos',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: GradientPreset.sunset.foreground(
                          theme.brightness,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
