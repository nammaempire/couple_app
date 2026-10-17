import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/voice_clip_player.dart';
import 'package:couple_app/features/chat/models/message.dart';

/// Play/pause button, progress bar and time for a voice message.
class VoiceMessagePlayer extends StatelessWidget {
  const VoiceMessagePlayer({
    super.key,
    required this.message,
    required this.color,
  });

  final Message message;

  /// Foreground colour, matching the bubble's text.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return VoiceClipPlayer(
      clipId: message.id,
      url: message.mediaUrl,
      duration: message.duration,
      color: color,
    );
  }
}
