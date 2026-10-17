import 'package:flutter/material.dart';

import 'package:couple_app/features/calls/data/agora_service.dart';

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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ControlButton(
          icon: agora.micMuted ? Icons.mic_off : Icons.mic,
          active: agora.micMuted,
          tooltip: agora.micMuted ? 'Unmute' : 'Mute',
          onPressed: agora.isReady ? agora.toggleMic : null,
        ),
        const SizedBox(width: 14),

        if (isVideo) ...[
          _ControlButton(
            icon: agora.cameraOff ? Icons.videocam_off : Icons.videocam,
            active: agora.cameraOff,
            tooltip: agora.cameraOff ? 'Camera on' : 'Camera off',
            onPressed: agora.isReady ? agora.toggleCamera : null,
          ),
          const SizedBox(width: 14),
          _ControlButton(
            icon: Icons.cameraswitch,
            tooltip: 'Flip camera',
            onPressed: agora.isReady ? agora.switchCamera : null,
          ),
        ] else
          _ControlButton(
            icon: agora.speakerOn ? Icons.volume_up : Icons.phone_in_talk,
            active: agora.speakerOn,
            tooltip: agora.speakerOn ? 'Speaker off' : 'Speaker on',
            onPressed: agora.isReady ? agora.toggleSpeaker : null,
          ),

        const SizedBox(width: 14),
        _ControlButton(
          icon: Icons.call_end,
          background: const Color(0xFFE23D50),
          iconColor: Colors.white,
          tooltip: 'End call',
          onPressed: onHangUp,
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.background,
    this.iconColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final Color? background;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final bg =
        background ??
        (active ? Colors.white : Colors.white.withValues(alpha: .16));
    final fg = iconColor ?? (active ? Colors.black87 : Colors.white);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Icon(icon, color: fg, size: 26),
          ),
        ),
      ),
    );
  }
}
