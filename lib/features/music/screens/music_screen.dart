import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/empty_state.dart';
import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/music/data/media_shelf.dart';
import 'package:couple_app/features/music/data/music_service.dart';
import 'package:couple_app/features/music/data/song_link_launcher.dart';
import 'package:couple_app/features/music/models/song.dart';
import 'package:couple_app/features/music/providers/music_providers.dart';
import 'package:couple_app/features/music/screens/listen_together_screen.dart';
import 'package:couple_app/features/music/screens/song_editor_screen.dart';
import 'package:couple_app/features/music/widgets/listening_now_card.dart';
import 'package:couple_app/features/music/widgets/moment_look.dart';
import 'package:couple_app/features/music/widgets/music_empty_state.dart';
import 'package:couple_app/features/music/widgets/song_details_sheet.dart';
import 'package:couple_app/features/music/widgets/song_tile.dart';
import 'package:couple_app/features/music/widgets/video_card.dart';

/// The couple's songs and videos, saved as links, with "listen together" or
/// "watch together" on every one. Lives in the Together tab.
class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key, this.initialShelf = MediaShelf.songs});

  final MediaShelf initialShelf;

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  late MediaShelf _shelf = widget.initialShelf;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<MediaShelf>(
              segments: const [
                ButtonSegment(
                  value: MediaShelf.songs,
                  icon: Icon(Icons.music_note_outlined),
                  label: Text('Songs'),
                ),
                ButtonSegment(
                  value: MediaShelf.videos,
                  icon: Icon(Icons.smart_display_outlined),
                  label: Text('Videos'),
                ),
              ],
              selected: {_shelf},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _shelf = s.first),
            ),
          ),
        ),
        Expanded(
          child: MediaLibrary(key: ValueKey(_shelf), shelf: _shelf),
        ),
      ],
    );
  }
}

/// One shelf of the library: songs as tiles, videos as big 16:9 cards.
class MediaLibrary extends ConsumerStatefulWidget {
  const MediaLibrary({super.key, required this.shelf});

  final MediaShelf shelf;

  @override
  ConsumerState<MediaLibrary> createState() => _MediaLibraryState();
}

class _MediaLibraryState extends ConsumerState<MediaLibrary> {
  late final String _coupleId;
  late final String _myUid;
  late final MusicService _service;
  late final SongLinkLauncher _launch;

  final _search = TextEditingController();
  String _query = '';
  SongMoment? _moment;
  bool _bothOnly = false;

  /// Starting a session (or opening the player): ignore more taps.
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
    _service = ref.read(mediaServiceProvider(widget.shelf));
    _launch = ref.read(songLinkLauncherProvider);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  MediaShelf get _shelf => widget.shelf;
  bool get _videos => _shelf == MediaShelf.videos;

  bool get _filtering =>
      _query.trim().isNotEmpty || _moment != null || _bothOnly;

  void _clearFilters() {
    _search.clear();
    setState(() {
      _query = '';
      _moment = null;
      _bothOnly = false;
    });
  }

  void _openEditor({Song? song}) {
    Navigator.of(context).push(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => SongEditorScreen(song: song, shelf: _shelf),
      ),
    );
  }

  Future<void> _toggleLove(Song song) async {
    try {
      await _service.setLoved(
        _coupleId,
        song.id,
        uid: _myUid,
        loved: !song.isLovedBy(_myUid),
      );
    } catch (_) {
      if (mounted) {
        context.showSnackMessage('Could not save. Check your connection.');
      }
    }
  }

  Future<void> _openExternally(Song song) async {
    final ok = await _launch(song.url);
    if (!ok && mounted) {
      context.showSnackMessage('Could not open ${song.source.label}.');
    }
  }

  /// Starts listening to [song] together (queueing what follows it in
  /// [shown]) and opens the player.
  Future<void> _listen(Song song, List<Song> shown) async {
    if (_starting) return;
    _starting = true;
    try {
      await _startListening(song, shown);
    } finally {
      _starting = false;
    }
  }

  Future<void> _startListening(Song song, List<Song> shown) async {
    final watched = ref.read(liveMediaSessionProvider(_shelf));
    final live = watched != null && watched.isActive(_service.clock.nowMs())
        ? watched
        : null;
    if (live != null && live.songId == song.id) {
      await ListenTogetherScreen.open(context, shelf: _shelf);
      return;
    }
    if (live != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Switch to ${song.displayTitle} for both of you?'),
          content: Text('“${live.displayTitle}” stops on both phones.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              child: const Text('Switch'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await _service.startSession(
        coupleId: _coupleId,
        song: song,
        uid: _myUid,
        queue: SongLists.queueAfter(shown, song.id),
      );
    } on ListeningException catch (e) {
      if (mounted) context.showSnackMessage(e.message);
      return;
    } catch (_) {
      if (mounted) {
        context.showSnackMessage('Could not start. Check your connection.');
      }
      return;
    }
    if (mounted) await ListenTogetherScreen.open(context, shelf: _shelf);
  }

  Future<void> _delete(Song song) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete this ${_shelf.item}?'),
        content: Text('“${song.displayTitle}” is removed for both of you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.delete(_coupleId, song.id);
    } catch (_) {
      if (mounted) {
        context.showSnackMessage('Could not delete. Check your connection.');
      }
    }
  }

  Future<void> _showDetails(Song song, List<Song> shown) async {
    final partnerName = ref.read(partnerNameProvider);
    final action = await showModalBottomSheet<SongAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SongDetailsSheet(
        song: song,
        shelf: _shelf,
        addedBy: song.addedBy == _myUid ? 'you' : partnerName,
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case SongAction.listenTogether:
        await _listen(song, shown);
      case SongAction.open:
        await _openExternally(song);
      case SongAction.edit:
        _openEditor(song: song);
      case SongAction.delete:
        await _delete(song);
    }
  }

  Widget _chips(List<Song> all) {
    final used = SongLists.momentsUsed(all);
    // Keep the selected filter visible even if its last song went away.
    final moments = _moment == null || used.contains(_moment)
        ? used
        : [...used, _moment!];
    // A handful of chips at most, so all are built (no lazy list).
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          FilterChip(
            label: const Text('All'),
            selected: _moment == null && !_bothOnly,
            showCheckmark: false,
            onSelected: (_) => setState(() {
              _moment = null;
              _bothOnly = false;
            }),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: FilterChip(
              label: const Text('Loved by both 💞'),
              selected: _bothOnly,
              showCheckmark: false,
              onSelected: (on) => setState(() => _bothOnly = on),
            ),
          ),
          for (final m in moments)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: FilterChip(
                label: Text('${m.emoji} ${m.label}'),
                selected: _moment == m,
                showCheckmark: false,
                onSelected: (on) => setState(() => _moment = on ? m : null),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final songs = ref.watch(mediaItemsProvider(_shelf));
    final watched = ref.watch(liveMediaSessionProvider(_shelf));
    // Re-checked on every rebuild: a forgotten session goes stale.
    final live = watched != null && watched.isActive(_service.clock.nowMs())
        ? watched
        : null;
    final partnerName = ref.watch(partnerNameProvider);
    final partnerUid = ref.watch(
      coupleProvider.select((c) => c.value?.partnerIdFor(_myUid)),
    );
    final all = songs.value ?? const <Song>[];
    final shown = SongLists.filter(
      all,
      moment: _moment,
      query: _query,
      bothLoveOnly: _bothOnly,
      myUid: _myUid,
      partnerUid: partnerUid,
    );

    SongMoment? liveMoment;
    for (final s in all) {
      if (s.id == live?.songId) liveMoment = s.moment;
    }
    final liveCard = live == null
        ? null
        : ListeningNowCard(
            preset: liveMoment?.preset ?? GradientPreset.blush,
            particles: liveMoment == null
                ? ParticleStyle.hearts
                : liveMoment.particles,
            session: live,
            clock: _service.clock,
            shelf: _shelf,
            partnerUid: partnerUid,
            partnerName: partnerName,
            onOpen: () => ListenTogetherScreen.open(context, shelf: _shelf),
          );

    final Widget body;
    if (!songs.hasValue && !songs.hasError) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!songs.hasValue) {
      body = EmptyState(
        icon: Icons.cloud_off,
        text: 'Could not load your ${_shelf.item}s.',
      );
    } else if (all.isEmpty) {
      body = LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ?liveCard,
                MusicEmptyState(
                  shelf: _shelf,
                  filtering: false,
                  onAdd: _openEditor,
                  onClearFilters: _clearFilters,
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 96),
        children: [
          ?liveCard,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: _videos
                    ? 'Search title, channel or note'
                    : 'Search title, artist or note',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: _chips(all),
          ),
          if (shown.isEmpty)
            MusicEmptyState(
              shelf: _shelf,
              filtering: _filtering,
              onAdd: _openEditor,
              onClearFilters: _clearFilters,
            )
          else if (_videos)
            for (final (i, s) in shown.indexed)
              EntranceAnimation(
                key: ValueKey(s.id),
                index: i,
                child: VideoCard(
                  video: s,
                  myUid: _myUid,
                  partnerUid: partnerUid,
                  isPlaying: live?.songId == s.id,
                  onTap: () => _showDetails(s, shown),
                  onToggleLove: () => _toggleLove(s),
                  onWatch: () => _listen(s, shown),
                ),
              )
          else
            for (final (i, s) in shown.indexed)
              EntranceAnimation(
                key: ValueKey(s.id),
                index: i,
                child: SongTile(
                  song: s,
                  myUid: _myUid,
                  partnerUid: partnerUid,
                  isPlaying: live?.songId == s.id,
                  onTap: () => _showDetails(s, shown),
                  onToggleLove: () => _toggleLove(s),
                  onListen: () => _listen(s, shown),
                ),
              ),
        ],
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-${_shelf.item}',
        onPressed: _openEditor,
        icon: const Icon(Icons.add),
        label: Text('Add ${_shelf.item}'),
      ),
      body: body,
    );
  }
}
