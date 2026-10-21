import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/features/calls/data/agora_service.dart';
import 'package:couple_app/features/calls/widgets/call_avatar_ring.dart';

/// The row of in-call buttons: mute, camera or speaker, and hang up.
class CallControls extends StatelessWidget {
  const CallControls({
    super.key,
    required this.agora,
    required this.isVideo,
    required this.onHangUp,
  });

  final AgoraService agora;
  final bool isVideo;
  final VoidCallback onHangUp;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(width: 12);
    return Center(
      child: GlassPanel(
        dark: true,
        radius: 44,
        padding: const EdgeInsets.all(10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassCallButton(
              icon: agora.micMuted ? Icons.mic_off : Icons.mic,
              active: agora.micMuted,
              tooltip: agora.micMuted ? 'Unmute' : 'Mute',
              onPressed: agora.isReady ? agora.toggleMic : null,
            ),
            gap,
            if (isVideo) ...[
              GlassCallButton(
                icon: agora.cameraOff ? Icons.videocam_off : Icons.videocam,
                active: agora.cameraOff,
                tooltip: agora.cameraOff ? 'Camera on' : 'Camera off',
                onPressed: agora.isReady ? agora.toggleCamera : null,
              ),
              gap,
              GlassCallButton(
                icon: Icons.cameraswitch,
                tooltip: 'Flip camera',
                onPressed: agora.isReady ? agora.switchCamera : null,
              ),
            ] else
              GlassCallButton(
                icon: agora.speakerOn ? Icons.volume_up : Icons.phone_in_talk,
                active: agora.speakerOn,
                tooltip: agora.speakerOn ? 'Speaker off' : 'Speaker on',
                onPressed: agora.isReady ? agora.toggleSpeaker : null,
              ),
            gap,
            GlassCallButton(
              icon: Icons.call_end,
              colors: const [Color(0xFFFF5F6D), Color(0xFFD7263D)],
              tooltip: 'End call',
              onPressed: onHangUp,
            ),
          ],
        ),
      ),
    );
  }
}
