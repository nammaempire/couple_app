import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// A finished recording.
class RecordedVoice {
  const RecordedVoice(this.file, this.duration);

  final File file;
  final Duration duration;
}

/// Why a recording could not start.
enum VoiceRecorderFailure { permissionDenied, startFailed }

/// Records short mono AAC voice clips to a temporary file.
///
/// Shared by the chat composer and the love-letter recorder. Listeners are
/// notified when recording starts or stops and on every [elapsed] tick.
class VoiceRecorder extends ChangeNotifier {
  VoiceRecorder({
    required this.filePrefix,
    this.maxLength = const Duration(minutes: 5),
    this.tick = const Duration(milliseconds: 200),
    this.onMaxLengthReached,
  });

  /// File name prefix inside the temporary directory, e.g. `voice`.
  final String filePrefix;

  /// Recording length at which [onMaxLengthReached] is called.
  final Duration maxLength;

  /// How often [elapsed] is refreshed while recording.
  final Duration tick;

  /// Called once when a recording reaches [maxLength]. The owner decides
  /// whether to stop and keep or send the clip.
  final VoidCallback? onMaxLengthReached;

  static const _config = RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 64000,
    sampleRate: 44100,
    numChannels: 1,
  );

  AudioRecorder? _recorder;
  Timer? _ticker;
  DateTime? _startedAt;
  bool _starting = false;
  bool _disposed = false;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  Duration _elapsed = Duration.zero;
  Duration get elapsed => _elapsed;

  /// Asks for the microphone and starts recording.
  ///
  /// Returns null on success. A second call while starting or recording is
  /// ignored and also returns null.
  Future<VoiceRecorderFailure?> start() async {
    if (_starting || _isRecording) return null;
    _starting = true;
    try {
      final recorder = _recorder ??= AudioRecorder();
      if (!await recorder.hasPermission()) {
        return VoiceRecorderFailure.permissionDenied;
      }
      if (_disposed) return null;
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/${filePrefix}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await recorder.start(_config, path: path);
      if (_disposed) {
        await recorder.cancel();
        return null;
      }
      await HapticFeedback.mediumImpact();
      if (_disposed) {
        await recorder.cancel();
        return null;
      }
      _isRecording = true;
      _startedAt = DateTime.now();
      _elapsed = Duration.zero;
      _ticker = Timer.periodic(tick, (_) => _onTick());
      _notify();
      return null;
    } catch (_) {
      return VoiceRecorderFailure.startFailed;
    } finally {
      _starting = false;
    }
  }

  void _onTick() {
    final from = _startedAt;
    if (from == null || _disposed) return;
    _elapsed = DateTime.now().difference(from);
    _notify();
    if (_elapsed >= maxLength) onMaxLengthReached?.call();
  }

  /// Stops recording and returns the clip, or null if nothing was recording.
  Future<RecordedVoice?> stop() async {
    final recorder = _recorder;
    if (recorder == null || !_isRecording) return null;
    final duration = _endSession();
    final path = await recorder.stop();
    if (path == null) return null;
    return RecordedVoice(File(path), duration);
  }

  /// Stops recording and throws the clip away.
  Future<void> cancel() async {
    final recorder = _recorder;
    if (recorder == null || !_isRecording) return;
    _endSession();
    await recorder.cancel();
  }

  Duration _endSession() {
    _ticker?.cancel();
    _ticker = null;
    _startedAt = null;
    _isRecording = false;
    _notify();
    return _elapsed;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    if (_isRecording) _recorder?.cancel();
    _recorder?.dispose();
    super.dispose();
  }
}
