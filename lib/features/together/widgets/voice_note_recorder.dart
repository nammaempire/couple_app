import 'package:flutter/material.dart';

import 'package:couple_app/core/services/voice_playback.dart';
import 'package:couple_app/core/services/voice_recorder.dart';
import 'package:couple_app/core/utils/duration_format.dart';
import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/voice_clip_player.dart';

/// Record, preview and discard a short voice letter.
class VoiceNoteRecorder extends StatefulWidget {
  const VoiceNoteRecorder({
    super.key,
    required this.onChanged,
    this.onRecordingChanged,
    this.maxLength = const Duration(minutes: 5),
  });

  /// Called with the recording, or null when it is discarded.
  final ValueChanged<RecordedVoice?> onChanged;

  /// Called when recording starts and stops, so the parent can hold off
  /// sending until the clip is finished.
  final ValueChanged<bool>? onRecordingChanged;
  final Duration maxLength;

  @override
  State<VoiceNoteRecorder> createState() => _VoiceNoteRecorderState();
}

class _VoiceNoteRecorderState extends State<VoiceNoteRecorder> {
  late final VoiceRecorder _voice = VoiceRecorder(
    filePrefix: 'letter',
    maxLength: widget.maxLength,
    tick: const Duration(milliseconds: 250),
    onMaxLengthReached: _stop,
  )..addListener(_onVoiceChanged);
  RecordedVoice? _clip;

  @override
  void dispose() {
    _voice.dispose();
    if (_clip != null) VoicePlayback.instance.stop();
    super.dispose();
  }

  void _onVoiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    final failure = await _voice.start();
    if (!mounted) return;
    switch (failure) {
      case VoiceRecorderFailure.permissionDenied:
        context.showSnackMessage(
          'Voice letters need microphone access. Enable it in Settings.',
        );
      case VoiceRecorderFailure.startFailed:
        context.showSnackMessage('Could not start recording.');
      case null:
        if (!_voice.isRecording) return;
        widget.onRecordingChanged?.call(true);
    }
  }

  Future<void> _stop() async {
    if (!_voice.isRecording) return;
    // stop() ends the session synchronously, so the parent hears about it
    // before the file is finalised.
    final stopping = _voice.stop();
    widget.onRecordingChanged?.call(false);
    final clip = await stopping;
    if (clip == null || !mounted) return;
    if (clip.duration < const Duration(seconds: 1)) {
      context.showSnackMessage('Too short. Try again.');
      return;
    }
    setState(() => _clip = clip);
    widget.onChanged(clip);
  }

  void _discard() {
    VoicePlayback.instance.stop();
    setState(() => _clip = null);
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final clip = _clip;

    Widget body;
    if (_voice.isRecording) {
      body = Row(
        children: [
          Icon(Icons.fiber_manual_record, color: scheme.error),
          const SizedBox(width: 8),
          Text(
            formatDuration(_voice.elapsed),
            style: theme.textTheme.titleMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('Recording…')),
          FilledButton.icon(
            onPressed: _stop,
            icon: const Icon(Icons.stop_rounded),
            label: const Text('Stop'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          ),
        ],
      );
    } else if (clip != null) {
      body = Row(
        children: [
          Expanded(
            child: VoiceClipPlayer(
              clipId: 'letter-preview-${clip.file.path}',
              url: Uri.file(clip.file.path).toString(),
              duration: clip.duration,
              color: scheme.onSurface,
              maxWidth: 400,
            ),
          ),
          IconButton(
            tooltip: 'Discard recording',
            icon: Icon(Icons.delete_outline, color: scheme.error),
            onPressed: _discard,
          ),
        ],
      );
    } else {
      body = Row(
        children: [
          Icon(Icons.mic_none_rounded, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Add a voice letter (optional)',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          FilledButton.tonal(
            onPressed: _start,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Record'),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: body,
    );
  }
}
