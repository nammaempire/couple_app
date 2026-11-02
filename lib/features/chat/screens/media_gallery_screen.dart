import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/media/media_navigation.dart';
import 'package:couple_app/core/utils/duration_format.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/chat/data/chat_service.dart';
import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/providers/chat_providers.dart';
import 'package:couple_app/features/chat/widgets/chat_privacy_scope.dart';

/// Every photo and video shared in the chat, grouped by month.
///
/// Part of the conversation, so screenshot alerts and blocking apply.
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

  /// Loaded so far, newest first; more load as you scroll down.
  final _media = <Message>[];
  bool _loading = false;
  bool _reachedEnd = false;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_media.isEmpty && !_loading && !_reachedEnd && !_failed) {
      _loadMore();
    }
  }

  /// Fetches the next page (older than what's loaded), leaving out anything
  /// "clear chat" has hidden.
  Future<void> _loadMore() async {
    if (_loading || _reachedEnd) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await ref
          .read(chatServiceProvider)
          .fetchMedia(
            _coupleId,
            clearedAt: ref.read(chatClearedAtProvider),
            before: _media.isEmpty ? null : _media.last.sentAt,
          );
      if (!mounted) return;
      setState(() {
        _media.addAll(page);
        _reachedEnd = page.length < ChatService.mediaPageSize;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.extentAfter < 600) _loadMore();
    return false;
  }

  _Filter _filter = _Filter.all;

  void _open(Message message) {
    if (message.type == MessageType.video) {
      final url = message.mediaUrl;
      if (url == null) return;
      openVideo(
        context,
        url,
        wrap: (viewer) =>
            ChatPrivacyScope(subject: ScreenshotSubject.video, child: viewer),
      );
    } else {
      final url = message.imageUrl;
      if (url == null) return;
      openPhoto(
        context,
        url,
        wrap: (viewer) =>
            ChatPrivacyScope(subject: ScreenshotSubject.photo, child: viewer),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ChatPrivacyScope(child: _buildScaffold(theme));
  }

  Widget _buildScaffold(ThemeData theme) {
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
      body: Builder(
        builder: (context) {
          final retry = TextButton.icon(
            onPressed: _loadMore,
            icon: const Icon(Icons.refresh),
            label: const Text('Could not load. Try again'),
          );
          if (_media.isEmpty) {
            if (_failed) return Center(child: retry);
            if (!_reachedEnd) {
              return const Center(child: CircularProgressIndicator());
            }
          }

          final items = _media.where((m) {
            return switch (_filter) {
              _Filter.all => true,
              _Filter.photos => m.type == MessageType.image,
              _Filter.videos => m.type == MessageType.video,
            };
          }).toList();

          if (items.isEmpty && _reachedEnd) {
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

          return NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: CustomScrollView(
              // Always scrollable, so a short first page (say, with the Videos
              // filter on) can still be pulled to load the next one.
              physics: const AlwaysScrollableScrollPhysics(),
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
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Center(
                      child: _failed
                          ? retry
                          : _reachedEnd
                          ? const SizedBox.shrink()
                          : _LoadMoreTrigger(
                              key: ValueKey(_media.length),
                              onShown: _loadMore,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A spinner at the end of the list that asks for the next page as soon as
/// it is built, so a page too short to scroll still loads the rest.
class _LoadMoreTrigger extends StatefulWidget {
  const _LoadMoreTrigger({super.key, required this.onShown});

  final VoidCallback onShown;

  @override
  State<_LoadMoreTrigger> createState() => _LoadMoreTriggerState();
}

class _LoadMoreTriggerState extends State<_LoadMoreTrigger> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onShown();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 24,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
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
