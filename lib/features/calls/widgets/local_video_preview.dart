import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:couple_app/features/calls/data/webrtc_call_engine.dart';

/// This phone's own camera, as a small rounded preview (mirrored, like a
/// selfie camera).
class LocalVideoPreview extends StatelessWidget {
  const LocalVideoPreview({super.key, required this.engine});

  final WebRtcCallEngine engine;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: RTCVideoView(
        engine.localRenderer,
        mirror: true,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      ),
    );
  }
}
