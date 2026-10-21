import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// What an in-app player is doing.
enum SongPlayerState {
  /// Nothing loaded yet, or loaded but never started.
  unstarted,

  /// Loaded and ready at a position, not playing.
  cued,
  buffering,
  playing,
  paused,
  ended,
}

/// Why an in-app player can't play a song.
enum SongPlayerError {
  none,

  /// The owner doesn't allow the video to be played outside YouTube.
  notEmbeddable,

  /// Removed, private, or the id is wrong.
  notFound,
  other,
}

/// A snapshot of an in-app player.
@immutable
class SongPlayerValue {
  const SongPlayerValue({
    this.state = SongPlayerState.unstarted,
    this.positionMs = 0,
    this.durationMs = 0,
    this.error = SongPlayerError.none,
  });

  final SongPlayerState state;

  /// Best-known position, in milliseconds.
  final int positionMs;

  /// Length of the song in milliseconds, or 0 while unknown.
  final int durationMs;
  final SongPlayerError error;

  /// Playing, or about to (buffering after a play).
  bool get isPlaying =>
      state == SongPlayerState.playing || state == SongPlayerState.buffering;

  bool get hasError => error != SongPlayerError.none;

  SongPlayerValue copyWith({
    SongPlayerState? state,
    int? positionMs,
    int? durationMs,
    SongPlayerError? error,
  }) => SongPlayerValue(
    state: state ?? this.state,
    positionMs: positionMs ?? this.positionMs,
    durationMs: durationMs ?? this.durationMs,
    error: error ?? this.error,
  );

  @override
  bool operator ==(Object other) =>
      other is SongPlayerValue &&
      other.state == state &&
      other.positionMs == positionMs &&
      other.durationMs == durationMs &&
      other.error == error;

  @override
  int get hashCode => Object.hash(state, positionMs, durationMs, error);
}

/// Plays songs inside the app (YouTube videos), driven by the listening
/// session rather than by its own controls.
///
/// The real one wraps the YouTube iframe player; tests and screenshots use
/// a fake that draws a placeholder and records calls.
abstract class SongPlayer {
  /// The player's state, position and errors.
  ValueListenable<SongPlayerValue> get value;

  /// Loads [mediaId] paused at [startMs], ready to start instantly.
  Future<void> cue(String mediaId, {int startMs = 0});

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(int positionMs);

  /// The player itself (16:9). [overlay] is drawn on top of the video,
  /// which a plain `Stack` can't do over a platform web view.
  Widget view({Widget? overlay});

  Future<void> dispose();
}

/// Makes a new player for the listen-together screen.
typedef SongPlayerFactory = SongPlayer Function();
