import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/memories/models/memory.dart';

/// The latest few memories as a horizontal row of covers.
class RecentMemoriesStrip extends StatelessWidget {
  const RecentMemoriesStrip({
    super.key,
    required this.memories,
    required this.onOpen,
    required this.onSeeAll,
    required this.onAdd,
  });

  final List<Memory> memories;
  final ValueChanged<Memory> onOpen;
  final VoidCallback onSeeAll;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent memories',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (memories.isNotEmpty)
              TextButton(onPressed: onSeeAll, child: const Text('See all')),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: memories.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              if (i == memories.length) {
                return _AddTile(onTap: onAdd, empty: memories.isEmpty);
              }
              final m = memories[i];
              final cover = m.coverUrl;
              return GestureDetector(
                onTap: () => onOpen(m),
                child: SizedBox(
                  width: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (cover != null)
                          CachedNetworkImage(
                            imageUrl: cover,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => Container(
                              color: scheme.surfaceContainerHighest,
                            ),
                            errorWidget: (_, _, _) => Container(
                              color: scheme.surfaceContainerHighest,
                            ),
                          )
                        else
                          Container(
                            color: scheme.primaryContainer,
                            alignment: Alignment.center,
                            child: Text(
                              MemoryAlbums.emojiFor(m.album),
                              style: const TextStyle(fontSize: 32),
                            ),
                          ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.center,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0x99000000)],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 10,
                          right: 10,
                          bottom: 8,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.title.isEmpty ? 'Untitled' : m.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                DateFormat.MMMd().format(m.date),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap, required this.empty});

  final VoidCallback onTap;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: empty ? 220 : 120,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: .4),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 6),
            Text(
              empty ? 'Add your first memory' : 'Add memory',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge,
            ),
          ],
        ),
      ),
    );
  }
}
