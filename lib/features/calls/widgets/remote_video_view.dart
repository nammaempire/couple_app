import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:couple_app/features/calls/data/webrtc_call_engine.dart';

/// The partner's camera feed, full screen during a video call.
class RemoteVideoView extends StatelessWidget {
  const RemoteVideoView({super.key, required this.engine});

  final WebRtcCallEngine engine;

  @override
  Widget build(BuildContext context) {
    return RTCVideoView(
      engine.remoteRenderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }
}
