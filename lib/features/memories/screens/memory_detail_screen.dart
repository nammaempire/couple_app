import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'package:couple_app/core/media/media_navigation.dart';
import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/features/app_lock/app_lock_controller.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/separation_providers.dart';
import 'package:couple_app/features/memories/data/memory_service.dart';
import 'package:couple_app/features/memories/models/memory.dart';
import 'package:couple_app/features/memories/providers/memory_providers.dart';
import 'package:couple_app/features/memories/screens/memory_editor_screen.dart';
import 'package:couple_app/features/memories/widgets/memory_fact_chip.dart';
import 'package:couple_app/features/memories/widgets/memory_look.dart';
import 'package:couple_app/features/memories/widgets/memory_media_page.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';

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
      await ref
          .read(appLockControllerProvider.notifier)
          .suspendWhile(
            SharePlus.instance.share(
              ShareParams(
                text: text,
                files: files.isEmpty ? null : files,
                sharePositionOrigin: box == null
                    ? null
                    : box.localToGlobal(Offset.zero) & box.size,
              ),
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
    final separating = ref.watch(separationActiveProvider);

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

        final b = theme.brightness;
        final preset = MemoryLook.presetFor(memory.album);
        final onPhoto = media.isNotEmpty;
        final darkHeader = onPhoto || preset.isDarkIn(b);
        final fg = onPhoto ? Colors.white : preset.foreground(b);
        final buttonStyle = IconButton.styleFrom(
          backgroundColor: darkHeader
              ? Colors.black.withValues(alpha: .28)
              : Colors.white.withValues(alpha: .6),
          foregroundColor: fg,
        );
        final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;

        final facts = GlassPanel(
          dark: darkHeader,
          radius: 22,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MemoryFactChip(
                icon: Icons.event_outlined,
                text: DateFormat.yMMMMEEEEd().format(memory.date),
                color: fg,
              ),
              if (memory.place != null) ...[
                const SizedBox(height: 8),
                MemoryFactChip(
                  icon: Icons.place_outlined,
                  text: memory.place!,
                  color: fg,
                ),
              ],
              const SizedBox(height: 8),
              MemoryFactChip(
                icon: Icons.photo_album_outlined,
                text:
                    '${MemoryAlbums.emojiFor(memory.album)} '
                    '${memory.album}',
                color: fg,
              ),
            ],
          ),
        );

        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              memory.title.isEmpty ? 'Untitled' : memory.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: fg,
                shadows: onPhoto
                    ? const [Shadow(color: Color(0x66000000), blurRadius: 8)]
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: facts),
          ],
        );

        final Widget header;
        if (onPhoto) {
          header = SizedBox(
            height: 420 + topInset - kToolbarHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  controller: _pages,
                  itemCount: media.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) => MemoryMediaPage(
                    media: media[i],
                    onTap: () => _openMedia(media[i]),
                  ),
                ),
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, .22, .5, 1],
                        colors: [
                          Color(0x59000000),
                          Color(0x00000000),
                          Color(0x1A000000),
                          Color(0xD1000000),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (media.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              for (var i = 0; i < media.length; i++)
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.only(right: 6),
                                  width: i == page ? 18 : 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(
                                      alpha: i == page ? 1 : .5,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      titleBlock,
                    ],
                  ),
                ),
              ],
            ),
          );
        } else {
          header = ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(32),
            ),
            child: AnimatedGradientCard(
              preset: preset,
              radius: 0,
              shadow: false,
              padding: EdgeInsets.zero,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: FloatingHearts(
                        count: 10,
                        seed: memory.id.hashCode,
                        opacity: preset.isDarkIn(b) ? .3 : .55,
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, topInset + 4, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 104,
                            height: 104,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(
                                alpha: preset.isDarkIn(b) ? .12 : .55,
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(
                                  alpha: preset.isDarkIn(b) ? .2 : .8,
                                ),
                                width: 2,
                              ),
                            ),
                            child: Text(
                              MemoryAlbums.emojiFor(memory.album),
                              style: const TextStyle(fontSize: 52),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        titleBlock,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            foregroundColor: fg,
            systemOverlayStyle: darkHeader
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            leading: Navigator.of(context).canPop()
                ? Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: BackButton(style: buttonStyle),
                  )
                : null,
            actions: [
              IconButton(
                tooltip: memory.favorite
                    ? 'Remove from favourites'
                    : 'Add to favourites',
                style: buttonStyle,
                icon: Icon(
                  memory.favorite ? Icons.favorite : Icons.favorite_border,
                  color: memory.favorite
                      ? (darkHeader
                            ? const Color(0xFFFF8FB1)
                            : theme.colorScheme.primary)
                      : fg,
                ),
                onPressed: () => _memoryService.setFavorite(
                  coupleId: _coupleId,
                  memoryId: memory.id,
                  favorite: !memory.favorite,
                ),
              ),
              // Nothing leaves the app while the pairing is ending.
              if (!separating) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Share or save',
                  style: buttonStyle,
                  icon: _sharing
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: fg,
                          ),
                        )
                      : const Icon(Icons.ios_share),
                  onPressed: _sharing ? null : () => _share(memory),
                ),
              ],
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                style: buttonStyle,
                iconColor: fg,
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
              const SizedBox(width: 8),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              header,
              if (memory.caption.isNotEmpty)
                EntranceAnimation(
                  child: TintedCard(
                    preset: preset,
                    strength: .45,
                    edge: true,
                    margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                    radius: 24,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.format_quote_rounded,
                          color: preset.accent(b),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            memory.caption,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
