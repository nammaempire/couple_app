import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/features/calls/data/webrtc_call_engine.dart';
import 'package:couple_app/features/calls/widgets/call_avatar_ring.dart';

/// The row of in-call buttons: mute, camera or speaker, and hang up.
class CallControls extends StatelessWidget {
  const CallControls({
    super.key,
    required this.engine,
    required this.isVideo,
    required this.onHangUp,
  });

  final WebRtcCallEngine engine;
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
              icon: engine.micMuted ? Icons.mic_off : Icons.mic,
              active: engine.micMuted,
              tooltip: engine.micMuted ? 'Unmute' : 'Mute',
              onPressed: engine.isReady ? engine.toggleMic : null,
            ),
            gap,
            if (isVideo) ...[
              GlassCallButton(
                icon: engine.cameraOff ? Icons.videocam_off : Icons.videocam,
                active: engine.cameraOff,
                tooltip: engine.cameraOff ? 'Camera on' : 'Camera off',
                onPressed: engine.isReady ? engine.toggleCamera : null,
              ),
              gap,
              GlassCallButton(
                icon: Icons.cameraswitch,
                tooltip: 'Flip camera',
                onPressed: engine.isReady ? engine.switchCamera : null,
              ),
            ] else
              GlassCallButton(
                icon: engine.speakerOn ? Icons.volume_up : Icons.phone_in_talk,
                active: engine.speakerOn,
                tooltip: engine.speakerOn ? 'Speaker off' : 'Speaker on',
                onPressed: engine.isReady ? engine.toggleSpeaker : null,
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
