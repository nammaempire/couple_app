// Fakes for the music feature, shared by its widget tests (and usable by
// screenshot tests): no database, no web view, no network.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:couple_app/features/music/data/media_shelf.dart';
import 'package:couple_app/features/music/data/music_service.dart';
import 'package:couple_app/features/music/data/server_clock.dart';
import 'package:couple_app/features/music/data/song_player.dart';
import 'package:couple_app/features/music/models/listening_session.dart';
import 'package:couple_app/features/music/models/song.dart';
import 'package:couple_app/features/music/models/song_link.dart';
import 'package:couple_app/features/music/widgets/song_artwork.dart';

/// Records calls instead of touching the database. Songs and the session are
/// set directly; [nowMs] is the server clock.
///
/// Its videos shelf ([videos], what `forShelf(MediaShelf.videos)` returns)
/// is another fake sharing this one's clock.
class FakeMusicService implements MusicService {
  FakeMusicService({
    List<Song> songs = const [],
    this._session,
    this.nowMs = 1000000,
    this.shelf = MediaShelf.songs,
    this._parent,
  }) : _songList = songs;

  int nowMs;
  final FakeMusicService? _parent;

  @override
  final MediaShelf shelf;

  FakeMusicService? _videos;

  /// The videos shelf.
  FakeMusicService get videos =>
      _videos ??= FakeMusicService(shelf: MediaShelf.videos, parent: this);

  @override
  MusicService forShelf(MediaShelf other) => other == shelf
      ? this
      : other == MediaShelf.videos
      ? videos
      : _parent ?? this;
  final calls = <String>[];
  final saved = <Song>[];

  /// Thrown by session changes when set.
  Object? sessionError;

  @override
  late final ServerClock clock =
      _parent?.clock ?? ServerClock(localNowMs: () => nowMs);

  List<Song> _songList;
  final _songs = StreamController<List<Song>>.broadcast();
  ListeningSession? _session;
  final _sessions = StreamController<ListeningSession?>.broadcast();

  set songs(List<Song> list) {
    _songList = list;
    _songs.add(list);
  }

  ListeningSession? get session => _session;
  set session(ListeningSession? s) {
    _session = s;
    _sessions.add(s);
  }

  @override
  Stream<List<Song>> watchSongs(String coupleId) async* {
    yield _songList;
    yield* _songs.stream;
  }

  @override
  Stream<ListeningSession?> watchSession(String coupleId) async* {
    yield _session;
    yield* _sessions.stream;
  }

  @override
  Future<String> save(String coupleId, Song song) async {
    saved.add(song);
    calls.add('save ${song.id.isEmpty ? 'new' : song.id}');
    return song.id.isEmpty ? 'new1' : song.id;
  }

  @override
  Future<void> setLoved(
    String coupleId,
    String songId, {
    required String uid,
    required bool loved,
  }) async => calls.add('loved $songId $loved');

  @override
  Future<void> delete(String coupleId, String songId) async =>
      calls.add('delete $songId');

  @override
  Future<void> calibrateClock(String coupleId, String uid) async {}

  @override
  Future<void> heartbeat(String coupleId, String uid) async =>
      calls.add('heartbeat');

  @override
  Future<void> leave(String coupleId, String uid) async => calls.add('leave');

  @override
  Future<void> startSession({
    required String coupleId,
    required Song song,
    required String uid,
    List<String> queue = const [],
  }) async {
    if (sessionError case final e?) throw e;
    calls.add('start ${song.id} ${queue.join(',')}');
    session = ListeningSession.start(
      song: song,
      uid: uid,
      nowMs: nowMs,
      queue: queue,
      previousVersion: _session?.version ?? 0,
    );
  }

  @override
  Future<void> setStatus({
    required String coupleId,
    required String uid,
    required ListeningStatus status,
    int? positionMs,
  }) async {
    if (sessionError case final e?) throw e;
    calls.add('status ${status.id}${positionMs == null ? '' : ' $positionMs'}');
  }

  @override
  Future<void> next({
    required String coupleId,
    required String uid,
    required String currentSongId,
  }) async {
    if (sessionError case final e?) throw e;
    calls.add('next $currentSongId');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// An in-app player that draws a placeholder and records what it was told.
/// Like the real one, play/pause/seek change its state straight away.
class FakeSongPlayer implements SongPlayer {
  FakeSongPlayer({this.durationMs = 200000});

  final int durationMs;
  final calls = <String>[];

  /// Pretends autoplay is blocked: play() is recorded but does nothing.
  bool blockPlay = false;
  final _value = ValueNotifier(const SongPlayerValue());
  bool disposed = false;

  @override
  ValueListenable<SongPlayerValue> get value => _value;

  /// Pretends the player reported [v].
  void emit(SongPlayerValue v) => _value.value = v;

  void emitPosition(int ms) => emit(_value.value.copyWith(positionMs: ms));

  void emitState(SongPlayerState state) =>
      emit(_value.value.copyWith(state: state));

  void emitError(SongPlayerError error) =>
      emit(_value.value.copyWith(error: error));

  @override
  Future<void> cue(String mediaId, {int startMs = 0}) async {
    calls.add('cue $mediaId $startMs');
    emit(
      SongPlayerValue(
        state: SongPlayerState.cued,
        positionMs: startMs,
        durationMs: durationMs,
      ),
    );
  }

  @override
  Future<void> play() async {
    calls.add('play');
    if (!blockPlay) emitState(SongPlayerState.playing);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    emitState(SongPlayerState.paused);
  }

  @override
  Future<void> seekTo(int positionMs) async {
    calls.add('seek $positionMs');
    emitPosition(positionMs);
  }

  @override
  Widget view({Widget? overlay}) => AspectRatio(
    aspectRatio: 16 / 9,
    child: Stack(
      fit: StackFit.expand,
      children: [
        const SongArtworkPlaceholder(source: SongSource.youtube, iconSize: 48),
        ?overlay,
      ],
    ),
  );

  @override
  Future<void> dispose() async {
    disposed = true;
    calls.add('dispose');
  }
}

/// A saved song for tests. No artwork by default, so nothing loads from
/// the network.
Song testSong(
  String id, {
  String title = '',
  String artist = '',
  SongSource source = SongSource.spotify,
  String mediaId = '',
  SongMoment moment = SongMoment.other,
  Set<String> lovedBy = const {},
  String addedBy = 'u1',
  String note = '',
  int playCount = 0,
  DateTime? createdAt,
}) {
  final inApp = source.playsInApp && mediaId.isNotEmpty;
  return Song(
    id: id,
    url: switch (source) {
      SongSource.youtube => 'https://www.youtube.com/watch?v=$mediaId',
      SongSource.spotify => 'https://open.spotify.com/track/${id}xxxxxxxxxx',
      _ => 'https://example.com/$id',
    },
    source: source,
    kind: inApp ? SongKind.video : SongKind.track,
    mediaId: mediaId,
    title: title,
    artist: artist,
    moment: moment,
    lovedBy: lovedBy,
    addedBy: addedBy,
    note: note,
    playCount: playCount,
    createdAt: createdAt,
  );
}

/// A live session for [song] at server time [at].
ListeningSession testSession(
  Song song, {
  ListeningStatus status = ListeningStatus.playing,
  int positionMs = 0,
  required int at,
  int version = 1,
  List<String> queue = const [],
  Map<String, int> listeners = const {},
}) => ListeningSession(
  songId: song.id,
  url: song.url,
  source: song.source,
  mediaId: song.mediaId,
  title: song.title,
  artist: song.artist,
  status: status,
  positionMs: positionMs,
  at: at,
  hostUid: 'u1',
  updatedBy: 'u1',
  version: version,
  queue: queue,
  listeners: listeners,
);
