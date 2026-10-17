import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// One audio player shared by every voice bubble, so starting a message
/// stops whichever one was playing.
class VoicePlayback extends ChangeNotifier {
  VoicePlayback._();

  static final VoicePlayback instance = VoicePlayback._();

  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;

  /// The message currently loaded, playing or paused.
  String? currentId;
  bool playing = false;
  bool loading = false;
  Duration position = Duration.zero;
  Duration? total;

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;

    final player = AudioPlayer();
    _stateSub = player.playerStateStream.listen((state) {
      playing =
          state.playing && state.processingState != ProcessingState.completed;
      loading =
          state.processingState == ProcessingState.loading ||
          state.processingState == ProcessingState.buffering;
      if (state.processingState == ProcessingState.completed) {
        position = Duration.zero;
        player.pause();
        player.seek(Duration.zero);
      }
      notifyListeners();
    });
    _positionSub = player.positionStream.listen((p) {
      position = p;
      notifyListeners();
    });
    return _player = player;
  }

  bool isCurrent(String messageId) => currentId == messageId;

  /// Plays [messageId] from [url], or pauses it if it is already playing.
  Future<void> toggle(String messageId, String url) async {
    final player = _ensurePlayer();

    if (currentId == messageId) {
      if (player.playing) {
        await player.pause();
      } else {
        unawaited(player.play());
      }
      return;
    }

    currentId = messageId;
    position = Duration.zero;
    total = null;
    loading = true;
    notifyListeners();

    try {
      await player.stop();
      final length = await player.setUrl(url);
      // Another message may have been tapped while this one loaded.
      if (currentId != messageId) return;
      total = length;
      notifyListeners();
      unawaited(player.play());
    } on PlayerInterruptedException {
      // Superseded by a newer tap; that tap owns the player now.
      return;
    } catch (_) {
      if (currentId != messageId) return;
      currentId = null;
      loading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> seek(String messageId, Duration to) async {
    if (currentId != messageId) return;
    await _player?.seek(to);
  }

  /// Stops playback, e.g. when leaving the chat.
  Future<void> stop() async {
    await _player?.stop();
    currentId = null;
    playing = false;
    position = Duration.zero;
    notifyListeners();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _player?.dispose();
    super.dispose();
  }
}
