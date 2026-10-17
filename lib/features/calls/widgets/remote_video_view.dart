import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';

import 'package:couple_app/features/calls/data/agora_service.dart';

/// The partner's camera feed, full screen during a video call.
class RemoteVideoView extends StatelessWidget {
  const RemoteVideoView({
    super.key,
    required this.agora,
    required this.uid,
    required this.channelName,
  });

  final AgoraService agora;
  final int uid;
  final String channelName;

  @override
  Widget build(BuildContext context) {
    final engine = agora.engine;
    if (engine == null) return const SizedBox.shrink();

    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: engine,
        canvas: VideoCanvas(uid: uid),
        connection: RtcConnection(channelId: channelName),
      ),
    );
  }
}
