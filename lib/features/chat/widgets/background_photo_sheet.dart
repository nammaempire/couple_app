import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/widgets/empty_state.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/providers/chat_providers.dart';
import 'package:couple_app/features/memories/models/memory.dart';
import 'package:couple_app/features/memories/providers/memory_providers.dart';

/// Where [BackgroundPhotoSheet] finds photos.
enum BackgroundPhotoSource { memories, chat }

/// A grid of photos the couple already has, from their memories or the
/// chat. Pops with the chosen photo's URL.
class BackgroundPhotoSheet extends ConsumerStatefulWidget {
  const BackgroundPhotoSheet({super.key, required this.source});

  final BackgroundPhotoSource source;

  @override
  ConsumerState<BackgroundPhotoSheet> createState() =>
      _BackgroundPhotoSheetState();
}

class _BackgroundPhotoSheetState extends ConsumerState<BackgroundPhotoSheet> {
  Future<List<String>>? _chatPhotos;

  @override
  void initState() {
    super.initState();
    if (widget.source == BackgroundPhotoSource.chat) {
      final chat = ref.read(chatServiceProvider);
      final coupleId = ref.read(currentCoupleIdProvider);
      _chatPhotos = chat
          .fetchMedia(coupleId)
          .then(
            (list) => [
              for (final m in list)
                if (m.type == MessageType.image && m.imageUrl != null)
                  m.imageUrl!,
            ],
          );
    }
  }

  static List<String> _memoryPhotos(List<Memory> memories) => [
    for (final memory in memories)
      for (final media in memory.media)
        if (!media.isVideo) media.url,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMemories = widget.source == BackgroundPhotoSource.memories;

    final Widget body;
    if (isMemories) {
      final memories = ref.watch(memoriesProvider);
      body = switch (memories) {
        AsyncValue(value: final list?) => _grid(_memoryPhotos(list)),
        AsyncValue(hasError: true) => _error(),
        _ => const Center(child: CircularProgressIndicator()),
      };
    } else {
      body = FutureBuilder<List<String>>(
        future: _chatPhotos,
        builder: (context, snap) {
          if (snap.hasError) return _error();
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _grid(snap.data!);
        },
      );
    }

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                isMemories ? 'From our memories' : 'From chat photos',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _error() => const EmptyState(
    icon: Icons.cloud_off,
    text: 'Could not load photos. Check your connection.',
    padding: EdgeInsets.all(24),
  );

  Widget _grid(List<String> urls) {
    if (urls.isEmpty) {
      return EmptyState(
        icon: Icons.photo_outlined,
        text: widget.source == BackgroundPhotoSource.memories
            ? 'No photos in your memories yet.'
            : 'No photos shared in the chat yet.',
        padding: const EdgeInsets.all(24),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: urls.length,
      itemBuilder: (context, i) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: scheme.surfaceContainerHighest),
            CachedNetworkImage(
              imageUrl: urls[i],
              memCacheWidth: 360,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => Icon(
                Icons.broken_image_outlined,
                color: scheme.onSurfaceVariant,
              ),
            ),
            Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: () => Navigator.pop(context, urls[i])),
            ),
          ],
        ),
      ),
    );
  }
}
