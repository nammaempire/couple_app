import 'dart:io';

import 'package:flutter/material.dart';

import 'package:couple_app/core/services/voice_recorder.dart';
import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/chat/models/message.dart';

/// Composer at the bottom of the chat: text, attachments, stickers, voice
/// recording, and the "replying to" banner.
///
/// With an empty text field the send button becomes a microphone. Tapping
/// it records until the user taps send (or the bin to discard).
class ChatInput extends StatefulWidget {
  const ChatInput({
    super.key,
    required this.onSendText,
    required this.onPickCamera,
    required this.onAttach,
    required this.onSendVoice,
    this.onOpenStickers,
    this.enabled = true,
    this.replyingTo,
    this.replyingToLabel,
    this.onCancelReply,
  });

  final Future<void> Function(String text) onSendText;
  final VoidCallback onPickCamera;

  /// Opens the photo/video attachment sheet.
  final VoidCallback onAttach;

  final Future<void> Function(File file, Duration duration) onSendVoice;

  /// Opens the couple sticker picker. The button is hidden when null.
  final VoidCallback? onOpenStickers;
  final bool enabled;

  final ReplyPreview? replyingTo;

  /// "You" or the partner's name, for the reply banner.
  final String? replyingToLabel;
  final VoidCallback? onCancelReply;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  static const _minRecording = Duration(milliseconds: 800);

  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _hasText = false;

  late final VoiceRecorder _voice = VoiceRecorder(
    filePrefix: 'voice',
    onMaxLengthReached: () => _finishRecording(send: true),
  )..addListener(_onVoiceChanged);

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void didUpdateWidget(covariant ChatInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Starting a reply focuses the field, like other messaging apps.
    if (widget.replyingTo != null &&
        widget.replyingTo?.messageId != oldWidget.replyingTo?.messageId) {
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _voice.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onVoiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    await widget.onSendText(text);
  }

  Future<void> _startRecording() async {
    final failure = await _voice.start();
    if (!mounted) return;
    switch (failure) {
      case VoiceRecorderFailure.permissionDenied:
        context.showSnackMessage(
          'Voice messages need microphone access. Enable it in Settings.',
        );
      case VoiceRecorderFailure.startFailed:
        context.showSnackMessage('Could not start recording.');
      case null:
        if (!_voice.isRecording) return;
        _focus.unfocus();
    }
  }

  Future<void> _finishRecording({required bool send}) async {
    if (!send) {
      await _voice.cancel();
      return;
    }

    final clip = await _voice.stop();
    if (clip == null) return;
    if (clip.duration < _minRecording) {
      if (!mounted) return;
      context.showSnackMessage(
        'Too short. Tap the mic and speak, then tap send.',
      );
      return;
    }
    await widget.onSendVoice(clip.file, clip.duration);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.dividerColor.withValues(alpha: .5)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.replyingTo != null)
              _ReplyBanner(
                reply: widget.replyingTo!,
                label: widget.replyingToLabel ?? '',
                onClose: widget.onCancelReply,
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: _voice.isRecording
                  ? _buildRecording(theme)
                  : _buildCompose(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompose() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          tooltip: 'Send a photo or video',
          icon: const Icon(Icons.add_circle_outline),
          onPressed: widget.enabled ? widget.onAttach : null,
        ),
        IconButton(
          tooltip: 'Take a photo',
          icon: const Icon(Icons.photo_camera_outlined),
          onPressed: widget.enabled ? widget.onPickCamera : null,
        ),
        if (widget.onOpenStickers != null)
          IconButton(
            tooltip: 'Stickers',
            icon: const Icon(Icons.emoji_emotions_outlined),
            onPressed: widget.enabled ? widget.onOpenStickers : null,
          ),
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            enabled: widget.enabled,
            minLines: 1,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: 'Message',
              contentPadding: EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 10,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        if (_hasText)
          IconButton.filled(
            tooltip: 'Send',
            onPressed: widget.enabled ? _send : null,
            icon: const Icon(Icons.send_rounded),
          )
        else
          IconButton.filledTonal(
            tooltip: 'Record a voice message',
            onPressed: widget.enabled ? _startRecording : null,
            icon: const Icon(Icons.mic_none_rounded),
          ),
      ],
    );
  }

  Widget _buildRecording(ThemeData theme) {
    final seconds = _voice.elapsed.inSeconds;
    final label =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

    return Row(
      children: [
        IconButton(
          tooltip: 'Discard',
          icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
          onPressed: () => _finishRecording(send: false),
        ),
        const SizedBox(width: 4),
        const _RecordingDot(),
        const SizedBox(width: 10),
        Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Recording…',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        IconButton.filled(
          tooltip: 'Send voice message',
          onPressed: () => _finishRecording(send: true),
          icon: const Icon(Icons.send_rounded),
        ),
      ],
    );
  }
}

class _RecordingDot extends StatefulWidget {
  const _RecordingDot();

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: .3, end: 1.0).animate(_blink),
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _ReplyBanner extends StatelessWidget {
  const _ReplyBanner({required this.reply, required this.label, this.onClose});

  final ReplyPreview reply;
  final String label;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to $label',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  reply.text.isEmpty ? 'Message' : reply.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cancel reply',
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
