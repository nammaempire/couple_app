import 'package:flutter/material.dart';

import 'package:couple_app/features/memories/models/memory.dart';

/// Photo and video counts over a memory's cover.
class MemoryCountBadge extends StatelessWidget {
  const MemoryCountBadge({super.key, required this.memory});

  final Memory memory;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (memory.photoCount > 0) ...[
            const Icon(Icons.photo, size: 14, color: Colors.white),
            const SizedBox(width: 3),
            Text(
              '${memory.photoCount}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
          if (memory.photoCount > 0 && memory.videoCount > 0)
            const SizedBox(width: 8),
          if (memory.videoCount > 0) ...[
            const Icon(Icons.videocam, size: 14, color: Colors.white),
            const SizedBox(width: 3),
            Text(
              '${memory.videoCount}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
