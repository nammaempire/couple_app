import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/app_lock/app_lock_controller.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/music/data/media_shelf.dart';
import 'package:couple_app/features/music/data/music_service.dart';
import 'package:couple_app/features/music/data/song_link_launcher.dart';
import 'package:couple_app/features/music/data/song_metadata_service.dart';
import 'package:couple_app/features/music/data/song_player.dart';
import 'package:couple_app/features/music/data/youtube_song_player.dart';
import 'package:couple_app/features/music/models/listening_session.dart';
import 'package:couple_app/features/music/models/song.dart';

final musicServiceProvider = Provider<MusicService>((ref) => MusicService());

final songMetadataServiceProvider = Provider<SongMetadataService>((ref) {
  final service = SongMetadataService();
  ref.onDispose(service.close);
  return service;
});

/// Every saved song, unsorted. Filter and sort with `SongLists`. After an
/// error the last good list is kept in `.value`.
final songsProvider = StreamProvider.autoDispose<List<Song>>(
  (ref) => ref
      .watch(musicServiceProvider)
      .watchSongs(ref.watch(currentCoupleIdProvider)),
);

/// The couple's listening session, or null if there has never been one.
/// The shell's banner watches it, so it stays subscribed while signed in.
final listeningSessionProvider = StreamProvider.autoDispose<ListeningSession?>(
  (ref) => ref
      .watch(musicServiceProvider)
      .watchSession(ref.watch(currentCoupleIdProvider)),
);

/// The live session (playing, paused or counting down), or null. A session
/// someone left running long ago with nobody listening counts as over
/// (see [ListeningSession.isStale]); this is checked whenever the session
/// changes or the provider is read again, which is often enough.
final liveSessionProvider = Provider.autoDispose<ListeningSession?>((ref) {
  final session = ref.watch(listeningSessionProvider).value;
  if (session == null) return null;
  final now = ref.watch(musicServiceProvider).clock.nowMs();
  return session.isActive(now) ? session : null;
});

// ---- Watch together (the videos shelf) -------------------------------------

/// Videos and the watching session. Shares the music service's database
/// and clock, so overriding [musicServiceProvider] covers both.
final videoServiceProvider = Provider<MusicService>(
  (ref) => ref.watch(musicServiceProvider).forShelf(MediaShelf.videos),
);

/// Every saved video, unsorted.
final videosProvider = StreamProvider.autoDispose<List<Song>>(
  (ref) => ref
      .watch(videoServiceProvider)
      .watchSongs(ref.watch(currentCoupleIdProvider)),
);

/// The couple's watching session, or null if there has never been one.
final watchingSessionProvider = StreamProvider.autoDispose<ListeningSession?>(
  (ref) => ref
      .watch(videoServiceProvider)
      .watchSession(ref.watch(currentCoupleIdProvider)),
);

/// The live, non-stale watching session, or null.
final liveWatchSessionProvider = Provider.autoDispose<ListeningSession?>((ref) {
  final session = ref.watch(watchingSessionProvider).value;
  if (session == null) return null;
  final now = ref.watch(videoServiceProvider).clock.nowMs();
  return session.isActive(now) ? session : null;
});

// ---- By shelf -----------------------------------------------------------------

/// The service for [shelf].
Provider<MusicService> mediaServiceProvider(MediaShelf shelf) =>
    switch (shelf) {
      MediaShelf.songs => musicServiceProvider,
      MediaShelf.videos => videoServiceProvider,
    };

/// The saved items on [shelf].
StreamProvider<List<Song>> mediaItemsProvider(MediaShelf shelf) =>
    switch (shelf) {
      MediaShelf.songs => songsProvider,
      MediaShelf.videos => videosProvider,
    };

/// The session for [shelf], live or not.
StreamProvider<ListeningSession?> mediaSessionProvider(MediaShelf shelf) =>
    switch (shelf) {
      MediaShelf.songs => listeningSessionProvider,
      MediaShelf.videos => watchingSessionProvider,
    };

/// The live, non-stale session for [shelf], or null.
Provider<ListeningSession?> liveMediaSessionProvider(MediaShelf shelf) =>
    switch (shelf) {
      MediaShelf.songs => liveSessionProvider,
      MediaShelf.videos => liveWatchSessionProvider,
    };

/// Makes the in-app (YouTube) player. Tests and screenshots override it
/// with a fake that needs no web view.
final songPlayerFactoryProvider = Provider<SongPlayerFactory>(
  (ref) => YoutubeSongPlayer.new,
);

/// Opens song links in their own apps, without the trip to Spotify or
/// YouTube locking the app. Tests override it to record calls.
final songLinkLauncherProvider = Provider<SongLinkLauncher>((ref) {
  final appLock = ref.watch(appLockControllerProvider.notifier);
  return (url) => appLock.suspendWhile(launchSongLink(url));
});

/// Remembers which session start ("shelf:coupleId:version") already opened its
/// external app on this phone, so closing and reopening the player during
/// the same song doesn't open Spotify a second time.
class LaunchedSessionNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void mark(String key) => state = key;
}

final launchedSessionProvider =
    NotifierProvider<LaunchedSessionNotifier, String?>(
      LaunchedSessionNotifier.new,
    );
