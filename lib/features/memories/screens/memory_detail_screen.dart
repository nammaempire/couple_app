import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'package:couple_app/core/media/media_navigation.dart';
import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/memories/data/memory_service.dart';
import 'package:couple_app/features/memories/models/memory.dart';
import 'package:couple_app/features/memories/providers/memory_providers.dart';
import 'package:couple_app/features/memories/screens/memory_editor_screen.dart';
import 'package:couple_app/features/memories/widgets/memory_fact_chip.dart';
import 'package:couple_app/features/memories/widgets/memory_media_page.dart';

/// One memory: its photos and videos full width, then the details.
class MemoryDetailScreen extends ConsumerStatefulWidget {
  const MemoryDetailScreen({
    super.key,
    required this.memoryId,
    this.initial,
    this.albums = const [],
  });

  final String memoryId;

  /// Shown immediately while the live copy loads.
  final Memory? initial;
  final List<String> albums;

  @override
  ConsumerState<MemoryDetailScreen> createState() => _MemoryDetailScreenState();
}

class _MemoryDetailScreenState extends ConsumerState<MemoryDetailScreen> {
  late final MemoryService _memoryService;
  late final String _coupleId;
  late final String _myUid;

  @override
  void initState() {
    super.initState();
    _memoryService = ref.read(memoryServiceProvider);
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
  }

  late final Stream<Memory?> _stream = _memoryService.watchMemory(
    _coupleId,
    widget.memoryId,
  );

  final _pages = PageController();
  int _page = 0;
  bool _sharing = false;
  bool _deleted = false;
  bool _closedForDeletion = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _openMedia(MemoryMedia media) {
    if (media.isVideo) {
      openVideo(context, media.url);
    } else {
      openPhoto(context, media.url);
    }
  }

  /// Exports the memory through the share sheet, so it can be saved to the
  /// gallery or sent elsewhere. Files come from the image cache when possible.
  Future<void> _share(Memory memory) async {
    setState(() => _sharing = true);
    try {
      final files = <XFile>[];
      for (final m in memory.media) {
        final file = await DefaultCacheManager().getSingleFile(m.url);
        files.add(XFile(file.path));
      }
      final text = [
        memory.title,
        if (memory.caption.isNotEmpty) memory.caption,
        [
          DateFormat.yMMMMd().format(memory.date),
          if (memory.place != null) memory.place!,
        ].join(' · '),
      ].join('\n');
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          files: files.isEmpty ? null : files,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (mounted) {
        context.showSnackMessage('Could not prepare this memory for sharing.');
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _delete(Memory memory) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this memory?'),
        content: const Text(
          'Its photos and videos will be removed for both of you. This '
          'cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      _deleted = true;
      await _memoryService.delete(coupleId: _coupleId, memory: memory);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      _deleted = false;
      if (mounted) {
        context.showSnackMessage(
          'Could not delete. Only the person who added it can.',
        );
      }
    }
  }

  void _edit(Memory memory) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            MemoryEditorScreen(memory: memory, existingAlbums: widget.albums),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<Memory?>(
      stream: _stream,
      initialData: widget.initial,
      builder: (context, snapshot) {
        final memory = snapshot.data;
        if (memory == null) {
          // Deleted (here or by the partner) while open.
          if (snapshot.connectionState == ConnectionState.active &&
              !_deleted &&
              !_closedForDeletion) {
            _closedForDeletion = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              // Remove this screen itself, not whatever is on top of it
              // (an editor or photo viewer the user may have open).
              final route = ModalRoute.of(context);
              if (route != null && route.isActive) {
                Navigator.of(context).removeRoute(route);
              }
            });
          }
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final media = memory.media;
        final page = media.isEmpty ? 0 : _page.clamp(0, media.length - 1);
        final canDelete = memory.createdBy == _myUid;

        return Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                tooltip: memory.favorite
                    ? 'Remove from favourites'
                    : 'Add to favourites',
                icon: Icon(
                  memory.favorite ? Icons.favorite : Icons.favorite_border,
                  color: memory.favorite ? theme.colorScheme.primary : null,
                ),
                onPressed: () => _memoryService.setFavorite(
                  coupleId: _coupleId,
                  memoryId: memory.id,
                  favorite: !memory.favorite,
                ),
              ),
              IconButton(
                tooltip: 'Share or save',
                icon: _sharing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share),
                onPressed: _sharing ? null : () => _share(memory),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') _edit(memory);
                  if (v == 'delete') _delete(memory);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (canDelete)
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              if (media.isNotEmpty) ...[
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: media.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) => MemoryMediaPage(
                      media: media[i],
                      onTap: () => _openMedia(media[i]),
                    ),
                  ),
                ),
                if (media.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < media.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == page ? 18 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: i == page
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      memory.title.isEmpty ? 'Untitled' : memory.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        MemoryFactChip(
                          icon: Icons.event_outlined,
                          text: DateFormat.yMMMMEEEEd().format(memory.date),
                        ),
                        if (memory.place != null)
                          MemoryFactChip(
                            icon: Icons.place_outlined,
                            text: memory.place!,
                          ),
                        MemoryFactChip(
                          icon: Icons.photo_album_outlined,
                          text:
                              '${MemoryAlbums.emojiFor(memory.album)} '
                              '${memory.album}',
                        ),
                      ],
                    ),
                    if (memory.caption.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        memory.caption,
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
