import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/media/media_navigation.dart';
import 'package:couple_app/core/utils/duration_format.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/providers/chat_providers.dart';

/// Every photo and video shared in the chat, grouped by month.
class MediaGalleryScreen extends ConsumerStatefulWidget {
  const MediaGalleryScreen({super.key});

  @override
  ConsumerState<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

enum _Filter { all, photos, videos }

class _MediaGalleryScreenState extends ConsumerState<MediaGalleryScreen> {
  late final String _coupleId;

  @override
  void initState() {
    super.initState();
    _coupleId = ref.read(currentCoupleIdProvider);
  }

  late Future<List<Message>> _media = ref
      .read(chatServiceProvider)
      .fetchMedia(_coupleId);
  _Filter _filter = _Filter.all;

  void _open(Message message) {
    if (message.type == MessageType.video) {
      final url = message.mediaUrl;
      if (url == null) return;
      openVideo(context, url);
    } else {
      final url = message.imageUrl;
      if (url == null) return;
      openPhoto(context, url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Photos & videos'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SegmentedButton<_Filter>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _Filter.all, label: Text('All')),
                ButtonSegment(value: _Filter.photos, label: Text('Photos')),
                ButtonSegment(value: _Filter.videos, label: Text('Videos')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<Message>>(
        future: _media,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _media = ref.read(chatServiceProvider).fetchMedia(_coupleId);
                }),
                icon: const Icon(Icons.refresh),
                label: const Text('Could not load. Try again'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data!.where((m) {
            return switch (_filter) {
              _Filter.all => true,
              _Filter.photos => m.type == MessageType.image,
              _Filter.videos => m.type == MessageType.video,
            };
          }).toList();

          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Photos and videos you send each other will collect here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            );
          }

          // Group into months, keeping newest first.
          final groups = <String, List<Message>>{};
          for (final m in items) {
            final key = m.sentAt == null
                ? 'Sending…'
                : DateFormat.yMMMM().format(m.sentAt!);
            groups.putIfAbsent(key, () => []).add(m);
          }

          return CustomScrollView(
            slivers: [
              for (final entry in groups.entries) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      entry.key,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 2,
                          crossAxisSpacing: 2,
                        ),
                    itemCount: entry.value.length,
                    itemBuilder: (context, i) => _Tile(
                      message: entry.value[i],
                      onTap: () => _open(entry.value[i]),
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.message, required this.onTap});

  final Message message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumb = message.imageUrl;
    final isVideo = message.type == MessageType.video;
    final duration = message.duration;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (thumb == null)
            Container(color: const Color(0xFF2A2124))
          else
            CachedNetworkImage(
              imageUrl: thumb,
              fit: BoxFit.cover,
              placeholder: (_, _) =>
                  Container(color: theme.colorScheme.surfaceContainerHighest),
              errorWidget: (_, _, _) => Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          if (isVideo)
            Positioned(
              left: 6,
              bottom: 6,
              child: Row(
                children: [
                  const Icon(
                    Icons.play_circle_fill,
                    color: Colors.white,
                    size: 18,
                  ),
                  if (duration != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      formatDuration(duration),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        shadows: [Shadow(blurRadius: 4)],
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
