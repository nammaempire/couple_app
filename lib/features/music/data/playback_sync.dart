import 'package:flutter/foundation.dart';

import 'package:couple_app/features/music/data/song_player.dart';
import 'package:couple_app/features/music/models/listening_session.dart';

/// What the in-app player should do to match the session.
@immutable
sealed class SyncAction {
  const SyncAction();
}

/// Already in step.
class SyncNone extends SyncAction {
  const SyncNone();
  @override
  bool operator ==(Object other) => other is SyncNone;
  @override
  int get hashCode => 0;
  @override
  String toString() => 'SyncNone()';
}

/// Load the session's song, paused at [atMs]; [thenPlay] when it should
/// already be playing (joining part-way through).
class SyncCue extends SyncAction {
  const SyncCue(this.atMs, {this.thenPlay = false});
  final int atMs;
  final bool thenPlay;
  @override
  bool operator ==(Object other) =>
      other is SyncCue && other.atMs == atMs && other.thenPlay == thenPlay;
  @override
  int get hashCode => Object.hash(atMs, thenPlay);
  @override
  String toString() => 'SyncCue($atMs, thenPlay: $thenPlay)';
}

/// Play, seeking to [seekToMs] first when it isn't null.
class SyncPlay extends SyncAction {
  const SyncPlay({this.seekToMs});
  final int? seekToMs;
  @override
  bool operator ==(Object other) =>
      other is SyncPlay && other.seekToMs == seekToMs;
  @override
  int get hashCode => seekToMs.hashCode;
  @override
  String toString() => 'SyncPlay(seekToMs: $seekToMs)';
}

/// Pause, seeking to [seekToMs] first when it isn't null.
class SyncPause extends SyncAction {
  const SyncPause({this.seekToMs});
  final int? seekToMs;
  @override
  bool operator ==(Object other) =>
      other is SyncPause && other.seekToMs == seekToMs;
  @override
  int get hashCode => seekToMs.hashCode;
  @override
  String toString() => 'SyncPause(seekToMs: $seekToMs)';
}

/// Counting down; both phones start in [msLeft].
class SyncWaitCountdown extends SyncAction {
  const SyncWaitCountdown(this.msLeft);
  final int msLeft;
  @override
  bool operator ==(Object other) =>
      other is SyncWaitCountdown && other.msLeft == msLeft;
  @override
  int get hashCode => msLeft.hashCode;
  @override
  String toString() => 'SyncWaitCountdown($msLeft)';
}

/// The song is over: move the session on to the next one.
class SyncNext extends SyncAction {
  const SyncNext();
  @override
  bool operator ==(Object other) => other is SyncNext;
  @override
  int get hashCode => 1;
  @override
  String toString() => 'SyncNext()';
}

/// No session, or it was stopped: stop the player.
class SyncEnded extends SyncAction {
  const SyncEnded();
  @override
  bool operator ==(Object other) => other is SyncEnded;
  @override
  int get hashCode => 2;
  @override
  String toString() => 'SyncEnded()';
}

/// Decides how the local player follows the shared session.
///
/// Pure apart from remembering when it last asked for a seek: right after
/// a seek the player still reports the old position for a moment, and
/// seeking again on that stale report would stutter forever.
class PlaybackSync {
  PlaybackSync({
    this.toleranceMs = 1500,
    this.pausedToleranceMs = 200,
    this.seekGraceMs = 2500,
  });

  /// Drift allowed while playing before seeking (see
  /// [ListeningSession.needsSeek]); seeking a playing song stutters.
  final int toleranceMs;

  /// Drift allowed while paused, where seeking can't be heard.
  final int pausedToleranceMs;

  /// After a seek, drift is ignored for this long.
  final int seekGraceMs;

  int? _lastSeekAt;

  /// Forgets the last seek, e.g. when a new song is loaded.
  void reset() => _lastSeekAt = null;

  /// What to do at server time [nowMs], given the [player]'s state and
  /// whether it has the session's song [loaded].
  SyncAction decide({
    required ListeningSession? session,
    required int nowMs,
    required SongPlayerValue player,
    required bool loaded,
  }) {
    if (session == null || !session.isLive) return const SyncEnded();
    final expected = session.expectedPositionMs(nowMs);

    switch (session.status) {
      case ListeningStatus.countdown when !session.countdownDone(nowMs):
        if (!loaded) return SyncCue(session.positionMs);
        // "Start together again" while it was playing: hold at the start.
        if (player.isPlaying) return _pause(session.positionMs, nowMs);
        return SyncWaitCountdown(session.countdownLeftMs(nowMs));

      case ListeningStatus.countdown || ListeningStatus.playing:
        if (!loaded) {
          _lastSeekAt = nowMs;
          return SyncCue(expected, thenPlay: true);
        }
        final duration = player.durationMs;
        if (player.state == SongPlayerState.ended ||
            (duration > 0 && expected >= duration + toleranceMs)) {
          return const SyncNext();
        }
        final drifted = _drifted(player.positionMs, expected, nowMs);
        if (!player.isPlaying) {
          if (drifted) _lastSeekAt = nowMs;
          return SyncPlay(seekToMs: drifted ? expected : null);
        }
        if (drifted) {
          _lastSeekAt = nowMs;
          return SyncPlay(seekToMs: expected);
        }
        return const SyncNone();

      case ListeningStatus.paused:
        final at = session.positionMs;
        if (!loaded) return SyncCue(at);
        // Seeking a paused video is silent, so pin it closely. No grace
        // period: a paused player's position doesn't move on its own.
        final off = ListeningSession.needsSeek(
          player.positionMs,
          at,
          toleranceMs: pausedToleranceMs,
        );
        if (player.isPlaying) return SyncPause(seekToMs: off ? at : null);
        if (!off) return const SyncNone();
        // Seeking a cued (never started) video starts it; load it again
        // at the right spot instead.
        if (player.state == SongPlayerState.cued ||
            player.state == SongPlayerState.unstarted) {
          return SyncCue(at);
        }
        return SyncPause(seekToMs: at);

      case ListeningStatus.ended:
        return const SyncEnded();
    }
  }

  SyncAction _pause(int atMs, int nowMs) =>
      SyncPause(seekToMs: _seek(atMs, nowMs));

  int _seek(int atMs, int nowMs) {
    _lastSeekAt = nowMs;
    return atMs;
  }

  bool _drifted(int actual, int expected, int nowMs) {
    final last = _lastSeekAt;
    if (last != null && nowMs - last < seekGraceMs) return false;
    return ListeningSession.needsSeek(
      actual,
      expected,
      toleranceMs: toleranceMs,
    );
  }
}
