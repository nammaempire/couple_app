import 'dart:io';

import 'package:flutter/material.dart';

import 'package:couple_app/core/services/voice_recorder.dart';
import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/widgets/chat_chrome.dart';
import 'package:couple_app/features/chat/widgets/chat_palette.dart';

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

    // A floating glass pill over the chat background, with the send / mic
    // button beside it.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.replyingTo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ChatGlass(
                  radius: 20,
                  child: _ReplyBanner(
                    reply: widget.replyingTo!,
                    label: widget.replyingToLabel ?? '',
                    onClose: widget.onCancelReply,
                  ),
                ),
              ),
            _voice.isRecording ? _buildRecording(theme) : _buildCompose(),
          ],
        ),
      ),
    );
  }

  Widget _buildCompose() {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    const compact = BoxConstraints.tightFor(width: 40, height: 44);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: ChatGlass(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Send a photo or video',
                  constraints: compact,
                  padding: EdgeInsets.zero,
                  color: theme.colorScheme.primary,
                  icon: const Icon(Icons.add_circle_rounded),
                  onPressed: widget.enabled ? widget.onAttach : null,
                ),
                if (widget.onOpenStickers != null)
                  IconButton(
                    tooltip: 'Stickers',
                    constraints: compact,
                    padding: EdgeInsets.zero,
                    color: muted,
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
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Message',
                      hintMaxLines: 1,
                      hintStyle: TextStyle(color: muted),
                      filled: false,
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Take a photo',
                  constraints: compact,
                  padding: EdgeInsets.zero,
                  color: muted,
                  icon: const Icon(Icons.photo_camera_outlined),
                  onPressed: widget.enabled ? widget.onPickCamera : null,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: _hasText
              ? _GradientAction(
                  key: const ValueKey('send'),
                  tooltip: 'Send',
                  icon: Icons.send_rounded,
                  onPressed: widget.enabled ? _send : null,
                )
              : _GradientAction(
                  key: const ValueKey('mic'),
                  tooltip: 'Record a voice message',
                  icon: Icons.mic_none_rounded,
                  onPressed: widget.enabled ? _startRecording : null,
                ),
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
        Expanded(
          child: ChatGlass(
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Discard',
                    icon: Icon(
                      Icons.delete_outline,
                      color: theme.colorScheme.error,
                    ),
                    onPressed: () => _finishRecording(send: false),
                  ),
                  const _RecordingDot(),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Recording…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _GradientAction(
          tooltip: 'Send voice message',
          icon: Icons.send_rounded,
          onPressed: () => _finishRecording(send: true),
        ),
      ],
    );
  }
}

/// The round send / mic button: the chat's accent gradient with a soft
/// glow.
class _GradientAction extends StatelessWidget {
  const _GradientAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = ChatPalette.of(context);
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: enabled ? 1 : .5,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: ChatPalette.diagonal(palette.accentGradient),
            boxShadow: [
              BoxShadow(
                color: palette.accentGradient.first.withValues(alpha: .35),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox.square(
                dimension: 50,
                child: Icon(icon, color: palette.onAccent, size: 24),
              ),
            ),
          ),
        ),
      ),
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
      padding: const EdgeInsets.fromLTRB(14, 6, 2, 6),
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
