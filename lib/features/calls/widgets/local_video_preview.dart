import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';

import 'package:couple_app/features/calls/data/agora_service.dart';

/// This phone's own camera, as a small rounded preview.
class LocalVideoPreview extends StatelessWidget {
  const LocalVideoPreview({super.key, required this.agora});

  final AgoraService agora;

  @override
  Widget build(BuildContext context) {
    final engine = agora.engine;
    if (engine == null) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AgoraVideoView(
        controller: VideoViewController(
          rtcEngine: engine,
          canvas: const VideoCanvas(uid: 0),
        ),
      ),
    );
  }
}
