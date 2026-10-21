import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/music/data/media_shelf.dart';
import 'package:couple_app/features/music/data/music_service.dart';
import 'package:couple_app/features/music/data/song_metadata_service.dart';
import 'package:couple_app/features/music/models/song.dart';
import 'package:couple_app/features/music/models/song_link.dart';
import 'package:couple_app/features/music/providers/music_providers.dart';
import 'package:couple_app/features/music/widgets/moment_look.dart';
import 'package:couple_app/features/music/widgets/song_link_preview.dart';

/// Add a song (or, on the videos shelf, a YouTube video) from a pasted
/// link, or edit a saved one's details.
///
/// The title is optional: without one the song shows as "Spotify link"
/// (see [Song.displayTitle]), so a link can be saved in one tap.
class SongEditorScreen extends ConsumerStatefulWidget {
  const SongEditorScreen({super.key, this.song, this.shelf = MediaShelf.songs});

  /// Songs, or videos to watch together (YouTube links only).
  final MediaShelf shelf;

  /// The song to edit; null to add one.
  final Song? song;

  /// How long typing pauses before the link is looked up.
  static const lookupDelay = Duration(milliseconds: 500);

  @override
  ConsumerState<SongEditorScreen> createState() => _SongEditorScreenState();
}

class _SongEditorScreenState extends ConsumerState<SongEditorScreen> {
  late final String _coupleId;
  late final String _myUid;
  late final MusicService _service;
  late final SongMetadataService _metadata;

  late final Song? _original = widget.song;
  final _linkText = TextEditingController();
  late final _title = TextEditingController(text: _original?.title ?? '');
  late final _artist = TextEditingController(text: _original?.artist ?? '');
  late final _note = TextEditingController(text: _original?.note ?? '');
  late String _thumbnail = _original?.thumbnailUrl ?? '';

  /// The moment chosen in the chips; until then, see [_momentFor].
  late SongMoment? _pickedMoment = _original?.moment;

  SongLink? _link;
  bool _linkInvalid = false;

  /// Fields the person typed into; lookups never overwrite them.
  bool _titleTouched = false;
  bool _artistTouched = false;

  Timer? _lookupDebounce;
  int _lookupSeq = 0;
  bool _lookingUp = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
    _service = ref.read(mediaServiceProvider(widget.shelf));
    _metadata = ref.read(songMetadataServiceProvider);
  }

  /// The chosen moment, or the default: the first song you add is
  /// probably "your song".
  bool get _videos => widget.shelf == MediaShelf.videos;

  SongMoment _momentFor(List<Song> all) =>
      _pickedMoment ??
      (_videos
          ? SongMoment.movieNight
          : all.isEmpty
          ? SongMoment.ourSong
          : SongMoment.other);

  /// Videos can only be YouTube videos: they play in the app's player.
  bool _wrongSource(SongLink? link) =>
      _videos && link != null && !link.playsInApp;

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _linkText.dispose();
    _title.dispose();
    _artist.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      context.showSnackMessage('Nothing to paste. Copy a song link first.');
      return;
    }
    _linkText.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _onLinkChanged(text);
  }

  void _onLinkChanged(String text) {
    final link = SongLink.parse(text);
    // Only a different link (after normalising) restarts the lookup;
    // editing around the same link leaves a pending lookup alone.
    final changed = link?.url != _link?.url;
    setState(() {
      _link = link;
      _linkInvalid = text.trim().isNotEmpty && link == null;
      if (changed) {
        _thumbnail = link?.fallbackThumbnail ?? '';
        // Details found for the old link don't belong to the new one;
        // what the person typed stays.
        if (!_titleTouched) _title.clear();
        if (!_artistTouched) _artist.clear();
        _lookingUp = link != null;
      }
    });
    if (!changed) return;
    _lookupDebounce?.cancel();
    // Also makes any lookup still in flight for the old link stale.
    final seq = ++_lookupSeq;
    if (link == null || _wrongSource(link)) {
      setState(() => _lookingUp = false);
      return;
    }
    _lookupDebounce = Timer(
      SongEditorScreen.lookupDelay,
      () => _lookup(link, seq),
    );
  }

  Future<void> _lookup(SongLink link, int seq) async {
    var found = SongMetadata.empty;
    try {
      found = await _metadata.lookup(link, asSong: !_videos);
    } catch (_) {
      // lookup() doesn't throw, but a stuck spinner would be worse.
    }
    // A newer link was pasted meanwhile (it owns the spinner now), or the
    // screen closed.
    if (!mounted || seq != _lookupSeq) return;
    setState(() {
      _lookingUp = false;
      if (!_titleTouched && found.title.isNotEmpty) _title.text = found.title;
      if (!_artistTouched && found.artist.isNotEmpty) {
        _artist.text = found.artist;
      }
      if (found.thumbnailUrl.isNotEmpty) _thumbnail = found.thumbnailUrl;
    });
  }

  Song? _duplicate(List<Song> all) {
    final link = _link;
    if (_original != null || link == null) return null;
    return SongLists.duplicateOf(all, link);
  }

  Future<void> _save() async {
    final original = _original;
    final link = _link;
    if (original == null) {
      if (link == null) {
        setState(() => _linkInvalid = _linkText.text.trim().isNotEmpty);
        if (_linkText.text.trim().isEmpty) {
          context.showSnackMessage('Paste a song link first.');
        }
        return;
      }
      if (_wrongSource(link) ||
          _duplicate(
                ref.read(mediaItemsProvider(widget.shelf)).value ?? const [],
              ) !=
              null) {
        return;
      }
    }

    final all =
        ref.read(mediaItemsProvider(widget.shelf)).value ?? const <Song>[];
    final base = original ?? Song.fromLink(link!, addedBy: _myUid);
    final song = base.copyWith(
      title: _title.text,
      artist: _artist.text,
      thumbnailUrl: _thumbnail,
      note: _note.text,
      moment: _momentFor(all),
    );

    setState(() => _saving = true);
    try {
      await _service.save(_coupleId, song);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showSnackMessage('Could not save. Check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final original = _original;
    final isEditing = original != null;
    final all =
        ref.watch(mediaItemsProvider(widget.shelf)).value ?? const <Song>[];
    final duplicate = _duplicate(all);
    final wrongSource = _wrongSource(_link);
    final noun = widget.shelf.item;
    final link = _link;

    final String? linkError;
    if (_linkInvalid) {
      linkError = 'That doesn’t look like a link';
    } else if (wrongSource) {
      linkError = 'Only YouTube links can be watched together for now';
    } else if (duplicate != null) {
      linkError = 'Already in your ${noun}s: ${duplicate.displayTitle}';
    } else {
      linkError = null;
    }

    final preview = original != null
        ? SongLinkPreview(
            source: original.source,
            playsInApp: original.playsInApp,
            title: _title.text,
            artist: _artist.text,
            thumbnailUrl: _thumbnail,
            preset: _momentFor(all).preset,
          )
        : link == null || wrongSource
        ? null
        : SongLinkPreview(
            source: link.source,
            playsInApp: link.playsInApp,
            title: _title.text,
            artist: _artist.text,
            thumbnailUrl: _thumbnail,
            loading: _lookingUp,
            preset: _momentFor(all).preset,
          );

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEditing ? 'Edit $noun' : 'Add a $noun'),
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: _saving ? null : () => Navigator.pop(context),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: _saving || duplicate != null || wrongSource
                    ? null
                    : _save,
                style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (!isEditing) ...[
              TextField(
                controller: _linkText,
                autofocus: true,
                keyboardType: TextInputType.url,
                autocorrect: false,
                onChanged: _onLinkChanged,
                decoration: InputDecoration(
                  labelText: _videos ? 'YouTube link' : 'Song link',
                  hintText: 'https://…',
                  prefixIcon: const Icon(Icons.link),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: TextButton(
                      onPressed: _paste,
                      child: const Text('Paste'),
                    ),
                  ),
                  helperText: _videos
                      ? 'A YouTube or YouTube Music video'
                      : 'Spotify, YouTube, YouTube Music, Apple Music, '
                            'JioSaavn or SoundCloud',
                  helperMaxLines: 2,
                  errorText: linkError,
                  errorMaxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (preview != null) ...[preview, const SizedBox(height: 20)],
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              maxLength: Song.maxTitle,
              onChanged: (_) => setState(() => _titleTouched = true),
              decoration: InputDecoration(
                labelText: 'Title',
                hintText: _videos ? 'e.g. Our trip vlog' : 'e.g. Tum Hi Ho',
                helperText: _title.text.trim().isEmpty
                    ? 'Optional. We fill it in from the link when we can.'
                    : null,
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _artist,
              textCapitalization: TextCapitalization.words,
              maxLength: Song.maxArtist,
              onChanged: (_) => setState(() => _artistTouched = true),
              decoration: InputDecoration(
                labelText: _videos ? 'Channel (optional)' : 'Artist (optional)',
                hintText: _videos ? 'e.g. T-Series' : 'e.g. Arijit Singh',
                counterText: '',
              ),
            ),
            const SizedBox(height: 20),
            Text('What it means to you', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m
                    in _videos ? SongMoment.forVideos : SongMoment.forSongs)
                  ChoiceChip(
                    label: Text('${m.emoji} ${m.label}'),
                    selected: _momentFor(all) == m,
                    onSelected: (_) => setState(() => _pickedMoment = m),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 6,
              maxLength: Song.maxNote,
              decoration: InputDecoration(
                labelText: _videos
                    ? 'Why watch it together (optional)'
                    : 'Why it’s yours (optional)',
                hintText: _videos
                    ? 'For our Friday movie night…'
                    : 'Played at our first dance…',
                prefixIcon: const Icon(Icons.favorite_outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
