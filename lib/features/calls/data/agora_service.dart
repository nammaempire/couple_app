import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:couple_app/core/config/agora_config.dart';

/// Thrown when a call cannot start — no App ID, or permissions refused.
class CallSetupException implements Exception {
  CallSetupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Wraps the Agora RTC engine: setup, joining, and the in-call controls.
///
/// One instance per call. Create it, [join], then [dispose] when the call ends.
class AgoraService extends ChangeNotifier {
  RtcEngine? _engine;

  /// Agora uid of the partner once they are in the channel.
  int? remoteUid;

  bool micMuted = false;
  bool cameraOff = false;
  bool speakerOn = true;

  /// True while the partner has been in the channel at least once, used to
  /// distinguish "connecting" from "they left".
  bool partnerHasJoined = false;

  /// Set by [dispose]. A join still in progress checks it after every await
  /// and tears itself down, so hanging up mid-join cannot leave the
  /// microphone or camera running.
  bool _disposed = false;

  bool get isReady => _engine != null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Releases an engine created by a join that was overtaken by [dispose].
  Future<Never> _abandon(RtcEngine? engine) async {
    if (engine != null) {
      try {
        await engine.leaveChannel();
        await engine.release();
      } catch (_) {}
    }
    if (identical(_engine, engine)) _engine = null;
    throw CallSetupException('The call ended.');
  }

  RtcEngine? get engine => _engine;

  /// Asks for the permissions a call needs. Video calls also need the camera.
  Future<void> _requestPermissions({required bool video}) async {
    final needed = <Permission>[
      Permission.microphone,
      if (video) Permission.camera,
    ];

    final statuses = await needed.request();
    final denied = statuses.entries
        .where((entry) => !entry.value.isGranted)
        .map(
          (entry) => entry.key == Permission.camera ? 'camera' : 'microphone',
        )
        .toList();

    if (denied.isNotEmpty) {
      throw CallSetupException(
        'Calls need access to your ${denied.join(' and ')}. '
        'Enable it in Settings and try again.',
      );
    }
  }

  /// Boots the engine, wires up event handlers, and joins [channelName].
  Future<void> join({required String channelName, required bool video}) async {
    if (!AgoraConfig.isConfigured) {
      throw CallSetupException(
        'Calling is not set up yet: no Agora App ID was provided.',
      );
    }

    await _requestPermissions(video: video);
    if (_disposed) await _abandon(null);

    final engine = createAgoraRtcEngine();
    _engine = engine;

    await engine.initialize(
      RtcEngineContext(
        appId: AgoraConfig.appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );
    if (_disposed) await _abandon(engine);

    engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          _notify();
        },
        onUserJoined: (connection, uid, elapsed) {
          remoteUid = uid;
          partnerHasJoined = true;
          _notify();
        },
        onUserOffline: (connection, uid, reason) {
          if (remoteUid == uid) remoteUid = null;
          _notify();
        },
        onLeaveChannel: (connection, stats) {
          remoteUid = null;
          _notify();
        },
      ),
    );

    if (video) {
      await engine.enableVideo();
      await engine.startPreview();
    } else {
      await engine.disableVideo();
      await engine.enableAudio();
    }

    await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    await engine.setEnableSpeakerphone(video);
    speakerOn = video;
    if (_disposed) await _abandon(engine);

    // Token is null because the Agora project runs in testing mode. A uid of
    // 0 lets Agora assign one.
    await engine.joinChannel(
      token: '',
      channelId: channelName,
      uid: 0,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );
    if (_disposed) await _abandon(engine);
  }

  Future<void> toggleMic() async {
    final engine = _engine;
    if (engine == null) return;
    micMuted = !micMuted;
    await engine.muteLocalAudioStream(micMuted);
    _notify();
  }

  Future<void> toggleCamera() async {
    final engine = _engine;
    if (engine == null) return;
    cameraOff = !cameraOff;
    await engine.muteLocalVideoStream(cameraOff);
    _notify();
  }

  Future<void> switchCamera() async {
    await _engine?.switchCamera();
  }

  Future<void> toggleSpeaker() async {
    final engine = _engine;
    if (engine == null) return;
    speakerOn = !speakerOn;
    await engine.setEnableSpeakerphone(speakerOn);
    _notify();
  }

  Future<void> leave() async {
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.leaveChannel();
      await engine.release();
    } catch (_) {
      // Tearing down a half-initialised engine should never crash the app.
    }
    _engine = null;
    remoteUid = null;
  }

  @override
  void dispose() {
    _disposed = true;
    leave();
    super.dispose();
  }
}
