import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:couple_app/features/memories/models/memory.dart';

/// One full-width page of a memory's photo/video carousel. Videos show a
/// play button over their frame.
class MemoryMediaPage extends StatelessWidget {
  const MemoryMediaPage({super.key, required this.media, required this.onTap});

  final MemoryMedia media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = media.previewUrl;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (preview != null)
            CachedNetworkImage(imageUrl: preview, fit: BoxFit.cover)
          else
            Container(color: const Color(0xFF2A2124)),
          if (media.isVideo)
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
