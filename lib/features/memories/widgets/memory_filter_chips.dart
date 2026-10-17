import 'package:flutter/material.dart';

import 'package:couple_app/features/memories/models/memory.dart';

/// Horizontal row of filter chips: all, favourites and one per album.
class MemoryFilterChips extends StatelessWidget {
  const MemoryFilterChips({
    super.key,
    required this.albums,
    required this.selected,
    required this.onSelected,
  });

  /// Special filter values alongside album names.
  static const allFilter = '__all__';
  static const favouritesFilter = '__favourites__';

  final List<String> albums;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    Widget chip(String value, String label) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected == value,
        onSelected: (_) => onSelected(value),
      ),
    );

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        children: [
          chip(allFilter, 'All'),
          chip(favouritesFilter, '♥ Favourites'),
          for (final album in albums)
            chip(album, '${MemoryAlbums.emojiFor(album)} $album'),
        ],
      ),
    );
  }
}
