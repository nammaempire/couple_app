import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/duration_format.dart';
import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/music/data/media_shelf.dart';
import 'package:couple_app/features/music/data/music_service.dart';
import 'package:couple_app/features/music/data/playback_sync.dart';
import 'package:couple_app/features/music/data/song_link_launcher.dart';
import 'package:couple_app/features/music/data/song_player.dart';
import 'package:couple_app/features/music/models/listening_session.dart';
import 'package:couple_app/features/music/models/song.dart';
import 'package:couple_app/features/music/models/song_link.dart';
import 'package:couple_app/features/music/providers/music_providers.dart';
import 'package:couple_app/features/music/widgets/listening_partners_header.dart';
import 'package:couple_app/features/music/widgets/moment_look.dart';
import 'package:couple_app/features/music/widgets/on_gradient_theme.dart';
import 'package:couple_app/features/music/widgets/song_artwork.dart';
import 'package:couple_app/features/music/widgets/song_source_style.dart';

/// The shared player: both phones play the same song at the same spot.
///
/// YouTube songs play inside the app and are kept in sync to the second;
/// other links count down together and open in their own app on both
/// phones at the same moment. Every control changes the shared session,
/// and the local player only ever follows it.
///
/// On the videos shelf it is [WatchTogetherScreen]: same engine, with a
/// landscape fullscreen mode.
class ListenTogetherScreen extends ConsumerStatefulWidget {
  const ListenTogetherScreen({super.key, this.shelf = MediaShelf.songs});

  /// Songs (listening) or videos (watching).
  final MediaShelf shelf;

  /// Players on screen (counted by their state, so a torn-down tree
  /// never leaves it stuck).
  static int _mounted = 0;

  /// Between [open] pushing and the screen's first frame.
  static bool _pushing = false;

  /// Whether the player is open, or being opened.
  static bool get isOpen => _mounted > 0 || _pushing;

  /// Pushes the player for [shelf], unless one is already open (a double
  /// tap, or the banner and the library racing).
  static Future<void> open(
    BuildContext context, {
    MediaShelf shelf = MediaShelf.songs,
  }) async {
    if (isOpen) return;
    _pushing = true;
    // The pushed screen builds (and counts itself) in the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pushing = false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => shelf == MediaShelf.videos
            ? const WatchTogetherScreen()
            : const ListenTogetherScreen(),
      ),
    );
  }

  @override
  ConsumerState<ListenTogetherScreen> createState() =>
      _ListenTogetherScreenState();
}

/// Watching a YouTube video together: [ListenTogetherScreen] on the videos
/// shelf.
class WatchTogetherScreen extends ListenTogetherScreen {
  const WatchTogetherScreen({super.key}) : super(shelf: MediaShelf.videos);
}

class _ListenTogetherScreenState extends ConsumerState<ListenTogetherScreen> {
  /// How often the player is checked against the session, and the
  /// countdown redrawn.
  static const _tickEvery = Duration(milliseconds: 250);
  static const _heartbeatEvery = Duration(seconds: 30);

  /// If playback hasn't started this long after asking, offer a button.
  static const _tapToPlayAfterMs = 3000;

  /// Joining an external song more than this long after it started
  /// doesn't open it by itself; "Open again" is there instead.
  static const _lateLaunchMs = 15000;

  late final String _coupleId;
  late final String _myUid;
  late final MusicService _service;
  late final SongLinkLauncher _launch;
  late final SongPlayerFactory _playerFactory;

  final _sync = PlaybackSync();
  SongPlayer? _player;

  /// "songId|mediaId" the player has loaded, or null.
  String? _loadedKey;

  /// A YouTube song that wouldn't play here, and why.
  String? _fallbackSongId;
  SongPlayerError _fallbackError = SongPlayerError.none;

  /// "songId@version" this phone already asked to move on from.
  String? _nextRequestedFor;

  /// Local time playback was asked to start and hasn't yet.
  int? _playRequestedAt;

  /// Slider position while dragging.
  double? _dragMs;
  bool _syncing = false;

  Timer? _tick;
  Timer? _heartbeat;

  /// Landscape, video only (videos shelf).
  bool _fullscreen = false;

  /// Fullscreen controls showing; a tap on the video toggles them.
  bool _chrome = true;

  /// Keeps the player's web view alive when it moves in and out of
  /// fullscreen.
  final _videoKey = GlobalKey();

  MediaShelf get _shelf => widget.shelf;

  @override
  void initState() {
    super.initState();
    ListenTogetherScreen._mounted++;
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
    _service = ref.read(mediaServiceProvider(widget.shelf));
    _launch = ref.read(songLinkLauncherProvider);
    _playerFactory = ref.read(songPlayerFactoryProvider);

    unawaited(
      _service.calibrateClock(_coupleId, _myUid).then((_) => _syncNow()),
    );
    unawaited(_service.heartbeat(_coupleId, _myUid));
    _heartbeat = Timer.periodic(
      _heartbeatEvery,
      (_) => _service.heartbeat(_coupleId, _myUid),
    );
    _tick = Timer.periodic(_tickEvery, (_) {
      _syncNow();
      if (mounted) setState(() {});
    });
    ref.listenManual(
      mediaSessionProvider(widget.shelf),
      // After the current frame's work: following the session can update
      // the player, which rebuilds this screen.
      (_, _) => scheduleMicrotask(_syncNow),
      onError: (_, _) {},
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncNow());
  }

  @override
  void dispose() {
    ListenTogetherScreen._mounted--;
    _tick?.cancel();
    _heartbeat?.cancel();
    unawaited(_service.leave(_coupleId, _myUid));
    _releasePlayer();
    if (_fullscreen) unawaited(_restoreSystemUi());
    super.dispose();
  }

  // ---- Sync -----------------------------------------------------------------

  ListeningSession? get _session =>
      ref.read(mediaSessionProvider(_shelf)).value;

  bool _isExternal(ListeningSession s) =>
      !s.playsInApp || _fallbackSongId == s.songId;

  SongPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = _playerFactory();
    player.value.addListener(_onPlayerChanged);
    return _player = player;
  }

  void _releasePlayer() {
    final player = _player;
    if (player == null) return;
    player.value.removeListener(_onPlayerChanged);
    _player = null;
    _loadedKey = null;
    _playRequestedAt = null;
    unawaited(player.dispose());
  }

  static String _fallbackText(SongPlayerError error) =>
      error == SongPlayerError.notFound
      ? 'This video was removed or is private, so it can’t play.'
      : 'This video can’t play inside the app, so it opens in YouTube.';

  void _onPlayerChanged() {
    final player = _player;
    if (player == null || !mounted) return;
    final value = player.value.value;
    if (value.isPlaying) _playRequestedAt = null;
    final session = _session;
    if (value.hasError &&
        session != null &&
        session.isLive &&
        _fallbackSongId != session.songId) {
      // Not embeddable, removed, or otherwise unplayable here.
      setState(() {
        _fallbackSongId = session.songId;
        _fallbackError = value.error;
      });
      _releasePlayer();
      context.showSnackMessage(_fallbackText(value.error));
      return;
    }
    if (value.state == SongPlayerState.ended) _syncNow();
    setState(() {});
  }

  /// Brings the player (or the external app) in line with the session.
  void _syncNow() {
    if (!mounted || _syncing) return;
    final session = _session;
    if (session == null) return;
    _syncing = true;
    try {
      final now = _service.clock.nowMs();
      if (!session.isLive) {
        _releasePlayer();
        return;
      }
      if (_isExternal(session)) {
        _releasePlayer();
        _maybeLaunch(session, now);
        return;
      }
      final player = _ensurePlayer();
      final key = '${session.songId}|${session.mediaId}';
      final loaded = _loadedKey == key;
      if (!loaded) _sync.reset();
      final action = _sync.decide(
        session: session,
        nowMs: now,
        player: player.value.value,
        loaded: loaded,
      );
      _apply(action, session, player, key);
    } finally {
      _syncing = false;
    }
  }

  void _apply(
    SyncAction action,
    ListeningSession session,
    SongPlayer player,
    String key,
  ) {
    switch (action) {
      case SyncCue(:final atMs, :final thenPlay):
        _loadedKey = key;
        _playRequestedAt = null;
        unawaited(() async {
          await player.cue(session.mediaId, startMs: atMs);
          if (thenPlay) {
            _notePlayRequested();
            await player.play();
          }
        }());
      case SyncPlay(:final seekToMs):
        _notePlayRequested();
        unawaited(() async {
          if (seekToMs != null) await player.seekTo(seekToMs);
          await player.play();
        }());
      case SyncPause(:final seekToMs):
        _playRequestedAt = null;
        unawaited(() async {
          await player.pause();
          if (seekToMs != null) await player.seekTo(seekToMs);
        }());
      case SyncNext():
        final marker = '${session.songId}@${session.version}';
        if (_nextRequestedFor == marker) return;
        _nextRequestedFor = marker;
        unawaited(
          _service
              .next(
                coupleId: _coupleId,
                uid: _myUid,
                currentSongId: session.songId,
              )
              .catchError((Object _) {}),
        );
      case SyncEnded():
        unawaited(player.pause());
      case SyncNone() || SyncWaitCountdown():
        break;
    }
  }

  void _notePlayRequested() {
    _playRequestedAt ??= _service.clock.localNowMs();
  }

  /// Opens an external song once per session start on this phone (even if
  /// the player is closed and reopened), when its countdown runs out.
  void _maybeLaunch(ListeningSession s, int now) {
    if (s.status != ListeningStatus.countdown || !s.countdownDone(now)) return;
    final key = '${_shelf.name}:$_coupleId:${s.version}';
    if (ref.read(launchedSessionProvider) == key) return;
    ref.read(launchedSessionProvider.notifier).mark(key);
    if (now - s.at > _lateLaunchMs) return;
    unawaited(_openLink(s));
  }

  Future<void> _openLink(ListeningSession s) async {
    final ok = await _launch(s.url);
    if (!ok && mounted) {
      context.showSnackMessage('Could not open ${s.source.label}.');
    }
  }

  // ---- Controls -------------------------------------------------------------

  /// Runs a session change, explaining failures.
  Future<void> _run(Future<void> Function() change) async {
    try {
      await change();
    } on ListeningException catch (e) {
      if (mounted) context.showSnackMessage(e.message);
    } catch (_) {
      if (mounted) {
        context.showSnackMessage('Could not sync. Check your connection.');
      }
    }
  }

  Future<void> _setStatus(ListeningStatus status, {int? positionMs}) => _run(
    () => _service.setStatus(
      coupleId: _coupleId,
      uid: _myUid,
      status: status,
      positionMs: positionMs,
    ),
  );

  Future<void> _togglePlay(ListeningSession s) => _setStatus(
    s.status == ListeningStatus.paused
        ? ListeningStatus.playing
        : ListeningStatus.paused,
  );

  Future<void> _seek(ListeningSession s, int ms) => _setStatus(
    s.status == ListeningStatus.paused
        ? ListeningStatus.paused
        : ListeningStatus.playing,
    positionMs: ms,
  );

  Future<void> _next(ListeningSession s) => _run(
    () => _service.next(
      coupleId: _coupleId,
      uid: _myUid,
      currentSongId: s.songId,
    ),
  );

  /// Playback didn't start by itself (a blocked autoplay): a tap here is
  /// a user gesture, so start it and jump to where the song should be.
  Future<void> _tapToPlay(ListeningSession s) async {
    final player = _player;
    if (player == null) return;
    setState(() => _playRequestedAt = null);
    await player.play();
    final at = s.expectedPositionMs(_service.clock.nowMs());
    await player.seekTo(math.max(0, at));
  }

  Future<void> _stop() async {
    final partnerName = ref.read(partnerNameProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop for both of you?'),
        content: Text('The music stops on your phone and $partnerName’s.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep listening'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (ok == true) await _setStatus(ListeningStatus.ended);
  }

  // ---- Fullscreen -----------------------------------------------------------

  Future<void> _enterFullscreen() async {
    setState(() {
      _fullscreen = true;
      _chrome = true;
    });
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _exitFullscreen() async {
    if (mounted) setState(() => _fullscreen = false);
    await _restoreSystemUi();
  }

  /// Back to the app's normal orientations and system bars.
  static Future<void> _restoreSystemUi() async {
    await SystemChrome.setPreferredOrientations(const []);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(mediaSessionProvider(_shelf));
    final session = sessionAsync.value;

    final Widget body;
    if (session == null && sessionAsync.hasError) {
      body = _ErrorView(
        onRetry: () => ref.invalidate(mediaSessionProvider(_shelf)),
      );
    } else if (session == null && sessionAsync.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (session == null || !session.isLive) {
      body = _EndedView(onBack: () => Navigator.pop(context));
    } else if (_fullscreen && !_isExternal(session)) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _exitFullscreen();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: _inAppVideo(
                context,
                session,
                _service.clock.nowMs(),
                fullscreen: true,
              ),
            ),
          ),
        ),
      );
    } else {
      body = _live(context, session);
    }
    if (_fullscreen) {
      // The session ended or the video can't play here: leave fullscreen.
      WidgetsBinding.instance.addPostFrameCallback((_) => _exitFullscreen());
    }

    final theme = Theme.of(context);
    final b = theme.brightness;
    final moment = _momentOf(session);
    final preset = moment.preset;
    final particles = moment.particles;
    final darkBg = preset.isDarkIn(b);
    final fg = preset.foreground(b);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: preset.colors(b).first,
      appBar: AppBar(
        title: Text(_shelf.togetherTitle),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        foregroundColor: fg,
        systemOverlayStyle: darkBg
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedGradientBackground(
              preset: preset,
              duration: const Duration(seconds: 12),
            ),
          ),
          if (particles != null)
            Positioned.fill(
              child: FloatingHearts(
                style: particles,
                color: moment.particleColor(b),
                count: particles == ParticleStyle.stars ? 30 : 14,
                opacity: particles == ParticleStyle.stars ? .75 : .5,
                seed: moment.index + 3,
              ),
            ),
          Positioned.fill(
            child: OnGradientTheme(
              preset: preset,
              child: SafeArea(bottom: false, child: body),
            ),
          ),
        ],
      ),
    );
  }

  /// What the playing song means to you two, which sets the screen's look.
  SongMoment _momentOf(ListeningSession? session) {
    final fallback = _shelf == MediaShelf.videos
        ? SongMoment.movieNight
        : SongMoment.romantic;
    if (session == null) return fallback;
    final songs = ref.watch(mediaItemsProvider(_shelf)).value;
    if (songs == null) return fallback;
    for (final s in songs) {
      if (s.id == session.songId) {
        return s.moment == SongMoment.other ? fallback : s.moment;
      }
    }
    return fallback;
  }

  /// The video (or artwork) and controls stay put at the top; only "Up
  /// next" and tips scroll. The web view must never sit in a scrolling
  /// list: its overlay isn't clipped and would be rebuilt as it scrolls.
  Widget _live(BuildContext context, ListeningSession session) {
    final now = _service.clock.nowMs();
    final partnerName = ref.watch(partnerNameProvider);
    final partnerUid = ref.watch(
      coupleProvider.select((c) => c.value?.partnerIdFor(_myUid)),
    );
    final songs = ref.watch(mediaItemsProvider(_shelf)).value ?? const <Song>[];
    final external = _isExternal(session);
    final partnerListening =
        partnerUid != null && session.isListening(partnerUid, now);

    final header = ListeningPartnersHeader(
      me: ref.watch(currentUserProvider),
      partner: ref.watch(partnerProvider).value,
      partnerName: partnerName,
      meListening: session.isListening(_myUid, now),
      partnerListening: partnerListening,
      doing: _shelf.doing,
    );
    final darkBg = _momentOf(
      session,
    ).preset.isDarkIn(Theme.of(context).brightness);
    final upNext = _UpNext(session: session, songs: songs, dark: darkBg);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        if (external) {
          final label = session.source.label;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: height * .8),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: GlassPanel(
                    dark: darkBg,
                    radius: 28,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    child: Column(
                      children: [
                        header,
                        const SizedBox(height: 12),
                        _externalPlayer(
                          context,
                          session,
                          now,
                          partnerName: partnerName,
                          partnerListening: partnerListening,
                          artworkSize: (height * .24).clamp(96.0, 200.0),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    upNext,
                    const SizedBox(height: 12),
                    Text(
                      'When the count hits zero, $label opens on both phones. '
                      'Press play in $label if it doesn’t start by itself.'
                      '${session.source == SongSource.spotify ? ' For to-the-second sync, start a Spotify Jam.' : ''}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        // Full width, so a 360-wide phone still gets a 200-high video.
        final videoHeight = width * 9 / 16;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: width,
              height: videoHeight,
              child: _inAppVideo(context, session, now),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(0, (height - videoHeight) * .8),
              ),
              // Scrolls only if large text makes the controls too tall.
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: GlassPanel(
                  dark: darkBg,
                  radius: 28,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      const SizedBox(height: 12),
                      _inAppControls(context, session, now),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [upNext],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _countdownNumber(BuildContext context, int msLeft) {
    final seconds = (msLeft / 1000).ceil().clamp(1, 9);
    return Text(
      '$seconds',
      key: const ValueKey('countdown'),
      style: Theme.of(context).textTheme.displayLarge?.copyWith(
        fontSize: 64,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    );
  }

  Widget _inAppVideo(
    BuildContext context,
    ListeningSession s,
    int now, {
    bool fullscreen = false,
  }) {
    final theme = Theme.of(context);
    final player = _ensurePlayer();
    final value = player.value.value;
    final counting =
        s.status == ListeningStatus.countdown && !s.countdownDone(now);
    final requested = _playRequestedAt;
    final stuck =
        !counting &&
        s.status != ListeningStatus.paused &&
        !value.isPlaying &&
        requested != null &&
        _service.clock.localNowMs() - requested > _tapToPlayAfterMs;

    Widget? overlay;
    if (counting) {
      overlay = ColoredBox(
        color: Colors.black54,
        child: Center(
          child: FittedBox(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Starting together in',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                  ),
                ),
                _countdownNumber(context, s.countdownLeftMs(now)),
              ],
            ),
          ),
        ),
      );
    } else if (stuck) {
      overlay = ColoredBox(
        color: Colors.black38,
        child: Center(
          child: FilledButton.icon(
            onPressed: () => _tapToPlay(s),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Tap to play'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          ),
        ),
      );
    }
    if (fullscreen) {
      overlay = Stack(
        fit: StackFit.expand,
        children: [
          // Taps on the video show or hide the controls.
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => setState(() => _chrome = !_chrome),
          ),
          ?overlay,
          if (_chrome) _fullscreenControls(context, s, player.value.value),
        ],
      );
    }
    return KeyedSubtree(
      key: _videoKey,
      child: player.view(overlay: overlay),
    );
  }

  /// Play/pause, seek and exit, over the bottom of the fullscreen video.
  Widget _fullscreenControls(
    BuildContext context,
    ListeningSession s,
    SongPlayerValue value,
  ) {
    final duration = value.durationMs;
    final shown = (_dragMs ?? value.positionMs.toDouble()).clamp(
      0.0,
      duration > 0 ? duration.toDouble() : 1.0,
    );
    final playing = s.status != ListeningStatus.paused;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        color: Colors.black54,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              IconButton(
                tooltip: playing ? 'Pause for both' : 'Play for both',
                color: Colors.white,
                onPressed: () => _togglePlay(s),
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
              Expanded(
                child: Slider(
                  value: shown,
                  max: duration > 0 ? duration.toDouble() : 1,
                  onChanged: duration > 0
                      ? (v) => setState(() => _dragMs = v)
                      : null,
                  onChangeEnd: duration > 0
                      ? (v) {
                          setState(() => _dragMs = null);
                          _seek(s, v.round());
                        }
                      : null,
                ),
              ),
              Text(
                '${formatDuration(Duration(milliseconds: shown.round()))}'
                '${duration > 0 ? ' / ${formatDuration(Duration(milliseconds: duration))}' : ''}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              IconButton(
                tooltip: 'Exit fullscreen',
                color: Colors.white,
                onPressed: _exitFullscreen,
                icon: const Icon(Icons.fullscreen_exit),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inAppControls(BuildContext context, ListeningSession s, int now) {
    final theme = Theme.of(context);
    final value = _ensurePlayer().value.value;
    final duration = value.durationMs;
    final position = _loadedKey == null
        ? math.max(0, s.expectedPositionMs(now))
        : value.positionMs;
    final shown = (_dragMs ?? position.toDouble()).clamp(
      0.0,
      duration > 0 ? duration.toDouble() : 1.0,
    );
    final playing = s.status != ListeningStatus.paused;
    final fg = theme.colorScheme.onSurface;
    final accent = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (s.artist.trim().isNotEmpty)
          Text(
            s.artist.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        Slider(
          value: shown,
          max: duration > 0 ? duration.toDouble() : 1,
          onChanged: duration > 0 ? (v) => setState(() => _dragMs = v) : null,
          onChangeEnd: duration > 0
              ? (v) {
                  setState(() => _dragMs = null);
                  _seek(s, v.round());
                }
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(Duration(milliseconds: shown.round())),
                style: theme.textTheme.labelMedium,
              ),
              Text(
                duration > 0
                    ? formatDuration(Duration(milliseconds: duration))
                    : '--:--',
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Stop for both',
              onPressed: _stop,
              color: fg,
              icon: const Icon(Icons.stop_rounded),
              iconSize: 30,
            ),
            const SizedBox(width: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: .35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: IconButton.filled(
                tooltip: playing ? 'Pause for both' : 'Play for both',
                onPressed: () => _togglePlay(s),
                iconSize: 36,
                padding: const EdgeInsets.all(12),
                style: IconButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              tooltip: 'Next ${_shelf.item}',
              onPressed: () => _next(s),
              color: fg,
              icon: const Icon(Icons.skip_next_rounded),
              iconSize: 30,
            ),
            if (_shelf == MediaShelf.videos) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Fullscreen',
                onPressed: _enterFullscreen,
                color: fg,
                icon: const Icon(Icons.fullscreen),
                iconSize: 30,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _externalPlayer(
    BuildContext context,
    ListeningSession s,
    int now, {
    required String partnerName,
    required bool partnerListening,
    required double artworkSize,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final counting =
        s.status == ListeningStatus.countdown && !s.countdownDone(now);
    final label = s.source.label;
    final fellBack = _fallbackSongId == s.songId;
    // A removed or private video won't open anywhere.
    final canOpen = !fellBack || _fallbackError != SongPlayerError.notFound;

    final Widget status;
    if (counting) {
      final seconds = (s.countdownLeftMs(now) / 1000).ceil().clamp(1, 9);
      status = Text(
        'Starting in $seconds…',
        key: const ValueKey('countdown'),
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.primary,
        ),
      );
    } else if (s.status == ListeningStatus.paused) {
      status = Text(
        'Paused',
        textAlign: TextAlign.center,
        style: theme.textTheme.titleMedium,
      );
    } else {
      status = Text(
        partnerListening
            ? 'Playing in $label on both phones'
            : 'Playing in $label — $partnerName will join when they open '
                  'the app',
        textAlign: TextAlign.center,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fellBack)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _fallbackText(_fallbackError),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
        Center(
          child: SongArtwork(
            url: s.thumbnailUrl,
            source: s.source,
            size: artworkSize,
            radius: 24,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          s.displayTitle,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (s.artist.trim().isNotEmpty)
          Text(
            s.artist.trim(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 8),
        Center(child: SongSourceBadge(source: s.source, dense: false)),
        const SizedBox(height: 16),
        status,
        const SizedBox(height: 16),
        if (!counting && canOpen) ...[
          FilledButton.icon(
            onPressed: () => _openLink(s),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open again'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _setStatus(ListeningStatus.countdown),
            icon: const Icon(Icons.replay),
            label: const Text('Start together again'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              onPressed: () => _next(s),
              icon: const Icon(Icons.skip_next_rounded),
              label: const Text('Next song'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            ),
            TextButton.icon(
              onPressed: _stop,
              icon: const Icon(Icons.stop_rounded),
              label: const Text('Stop for both'),
              style: TextButton.styleFrom(
                foregroundColor: scheme.error,
                minimumSize: const Size(0, 48),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The next few songs in the session's queue.
class _UpNext extends StatelessWidget {
  const _UpNext({
    required this.session,
    required this.songs,
    required this.dark,
  });

  final ListeningSession session;
  final List<Song> songs;

  /// On a dark background (smoky glass).
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final s in songs) s.id: s};
    final next = [for (final id in session.queue) ?byId[id]].take(3).toList();
    if (next.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Up next',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (final (i, song) in next.indexed)
          EntranceAnimation(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassPanel(
                dark: dark,
                radius: 18,
                padding: EdgeInsets.zero,
                child: _upNextTile(theme, song),
              ),
            ),
          ),
      ],
    );
  }

  Widget _upNextTile(ThemeData theme, Song song) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    leading: SongArtwork(
      url: song.thumbnailUrl,
      source: song.source,
      size: 40,
      radius: 10,
    ),
    title: Text(
      song.displayTitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: song.artist.trim().isEmpty
        ? null
        : Text(
            song.artist.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
    trailing: Text(song.moment.emoji, style: const TextStyle(fontSize: 18)),
  );
}

/// Shown when the session couldn't be loaded.
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Couldn’t reach your listening session',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
              style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the session was stopped (or there never was one).
class _EndedView extends StatelessWidget {
  const _EndedView({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.headphones_outlined,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Listening together ended',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Start another song from your library whenever you like.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onBack,
              style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
              child: const Text('Back to songs'),
            ),
          ],
        ),
      ),
    );
  }
}
