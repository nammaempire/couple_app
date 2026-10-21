import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'package:couple_app/features/music/data/song_player.dart';

/// [SongPlayer] on the YouTube iframe player.
///
/// YouTube's own controls are hidden and the video ignores taps, so the
/// only way to seek or pause is through the session (both phones follow).
/// The package already lets web views start sound without a tap
/// (`mediaPlaybackRequiresUserGesture` off on Android, no user action on
/// iOS); the screen still shows a hint if playback doesn't start.
class YoutubeSongPlayer implements SongPlayer {
  YoutubeSongPlayer()
    : _controller = YoutubePlayerController(
        params: const YoutubePlayerParams(
          showControls: false,
          showFullscreenButton: false,
          enableCaption: false,
          showVideoAnnotations: false,
          strictRelatedVideos: true,
          pointerEvents: PointerEvents.none,
          videoStateUpdateInterval: 250,
        ),
      ) {
    _valueSub = _controller.stream.listen(_onValue);
    _stateSub = _controller.videoStateStream.listen(
      (s) => _set(_value.value.copyWith(positionMs: s.position.inMilliseconds)),
    );
  }

  final YoutubePlayerController _controller;
  final _value = ValueNotifier(const SongPlayerValue());
  StreamSubscription<YoutubePlayerValue>? _valueSub;
  StreamSubscription<YoutubeVideoState>? _stateSub;
  String _mediaId = '';
  bool _disposed = false;

  @override
  ValueListenable<SongPlayerValue> get value => _value;

  void _set(SongPlayerValue v) {
    if (!_disposed) _value.value = v;
  }

  void _onValue(YoutubePlayerValue v) {
    final state = switch (v.playerState) {
      PlayerState.unknown || PlayerState.unStarted => SongPlayerState.unstarted,
      PlayerState.cued => SongPlayerState.cued,
      PlayerState.buffering => SongPlayerState.buffering,
      PlayerState.playing => SongPlayerState.playing,
      PlayerState.paused => SongPlayerState.paused,
      PlayerState.ended => SongPlayerState.ended,
    };
    final error = switch (v.error) {
      YoutubeError.none => SongPlayerError.none,
      YoutubeError.notEmbeddable ||
      YoutubeError.sameAsNotEmbeddable ||
      YoutubeError.sameAsNotEmbeddable2 => SongPlayerError.notEmbeddable,
      YoutubeError.videoNotFound ||
      YoutubeError.cannotFindVideo ||
      YoutubeError.invalidParam => SongPlayerError.notFound,
      YoutubeError.html5Error || YoutubeError.unknown => SongPlayerError.other,
    };
    final durationMs = v.metaData.duration.inMilliseconds;
    _set(
      _value.value.copyWith(
        state: state,
        error: error,
        durationMs: durationMs > 0 ? durationMs : null,
      ),
    );
    if (_value.value.durationMs == 0 &&
        (state == SongPlayerState.playing || state == SongPlayerState.cued)) {
      unawaited(_fetchDuration());
    }
  }

  Future<void> _fetchDuration() async {
    final seconds = await _guard(() => _controller.duration) ?? 0;
    if (seconds > 0) {
      _set(_value.value.copyWith(durationMs: (seconds * 1000).round()));
    }
  }

  /// Player calls wait for the iframe and can time out; a failure is not
  /// worth crashing for, since the next sync tick tries again.
  Future<T?> _guard<T>(Future<T> Function() call) async {
    if (_disposed) return null;
    try {
      return await call();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> cue(String mediaId, {int startMs = 0}) async {
    if (mediaId != _mediaId) {
      _mediaId = mediaId;
      _set(SongPlayerValue(positionMs: startMs));
    } else {
      _set(_value.value.copyWith(positionMs: startMs));
    }
    await _guard(
      () => _controller.cueVideoById(
        videoId: mediaId,
        startSeconds: startMs / 1000,
      ),
    );
  }

  @override
  Future<void> play() => _guard(_controller.playVideo);

  @override
  Future<void> pause() => _guard(_controller.pauseVideo);

  @override
  Future<void> seekTo(int positionMs) async {
    // Position reports only arrive while playing; remember the seek so a
    // paused player knows where it is.
    _set(_value.value.copyWith(positionMs: positionMs));
    await _guard(
      () =>
          _controller.seekTo(seconds: positionMs / 1000, allowSeekAhead: true),
    );
  }

  @override
  Widget view({Widget? overlay}) => YoutubePlayer(
    controller: _controller,
    backgroundColor: Colors.black,
    autoFullScreen: false,
    enableFullScreenOnVerticalDrag: false,
    controlsBuilder: overlay == null ? null : (_, _) => overlay,
  );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _valueSub?.cancel();
    await _stateSub?.cancel();
    _value.dispose();
    await _controller.close();
  }
}
