import 'package:flutter/material.dart';

import 'package:couple_app/features/memories/models/memory.dart';

/// Choice chips for picking a memory's album, plus a "New album" chip.
class MemoryAlbumPicker extends StatelessWidget {
  const MemoryAlbumPicker({
    super.key,
    required this.albums,
    required this.selected,
    required this.onSelected,
    required this.onNewAlbum,
  });

  final List<String> albums;
  final String selected;
  final ValueChanged<String> onSelected;
  final VoidCallback onNewAlbum;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final album in albums)
          ChoiceChip(
            label: Text('${MemoryAlbums.emojiFor(album)} $album'),
            selected: selected == album,
            onSelected: (_) => onSelected(album),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: const Text('New album'),
          onPressed: onNewAlbum,
        ),
      ],
    );
  }
}
