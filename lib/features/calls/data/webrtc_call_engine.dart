import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:couple_app/core/backend/backend.dart';
import 'package:couple_app/features/calls/data/call_signaling.dart';

/// Thrown when a call cannot start, e.g. permissions refused.
class CallSetupException implements Exception {
  CallSetupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Our own voice/video call engine on WebRTC (replaces Agora).
///
/// One instance per call: create it, [join], then [dispose] when the call
/// ends. The caller makes the offer, the callee answers; both trade network
/// candidates through [CallSignaling]. Audio and video then flow directly
/// between the phones, encrypted (DTLS-SRTP). If a direct path is blocked,
/// a TURN relay is used when the server provides one.
class WebRtcCallEngine extends ChangeNotifier {
  WebRtcCallEngine({
    required this.coupleId,
    required this.callId,
    required this.myUid,
    required this.partnerUid,
    required this.isCaller,
    required this.video,
    CallSignaling? signaling,
    this.functionsOverride,
  }) : _signaling = signaling ?? CallSignaling();

  final String coupleId;

  /// The call's id (its `channelName`); signals are scoped to it.
  final String callId;
  final String myUid;
  final String partnerUid;
  final bool isCaller;
  final bool video;

  final CallSignaling _signaling;

  /// Overrides [Functions.instance] (tests).
  final Functions? functionsOverride;

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  StreamSubscription<List<CallSignal>>? _signalSub;
  final _handled = <String>{};
  final _pendingRemoteCandidates = <RTCIceCandidate>[];
  final _outgoingCandidates = <Map<String, dynamic>>[];
  Timer? _candidateFlush;
  Timer? _restartTimer;
  bool _remoteDescriptionSet = false;
  bool _renderersReady = false;

  bool micMuted = false;
  bool cameraOff = false;
  bool speakerOn = true;

  /// True while media is flowing between the phones.
  bool remoteConnected = false;

  /// True once the phones have connected at least once, to tell
  /// "connecting" apart from "reconnecting".
  bool partnerHasJoined = false;

  /// True once the partner's video track has arrived.
  bool hasRemoteVideo = false;

  /// Set by [dispose]; a join still in progress stops at its next step.
  bool _disposed = false;

  bool get isReady => _pc != null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _checkAlive() {
    if (_disposed) throw CallSetupException('The call ended.');
  }

  Future<void> _requestPermissions() async {
    final needed = <Permission>[
      Permission.microphone,
      if (video) Permission.camera,
    ];
    final statuses = await needed.request();
    final denied = statuses.entries
        .where((e) => !e.value.isGranted)
        .map((e) => e.key == Permission.camera ? 'camera' : 'microphone')
        .toList();
    if (denied.isNotEmpty) {
      throw CallSetupException(
        'Calls need access to your ${denied.join(' and ')}. '
        'Enable it in Settings and try again.',
      );
    }
  }

  /// STUN (and TURN when configured) from the server; STUN if it can't say.
  Future<List<Map<String, dynamic>>> _iceServers() async {
    try {
      final functions = functionsOverride ?? Functions.instance;
      final res = await functions
          .call('iceServers')
          .timeout(const Duration(seconds: 6));
      final list = (res as Map?)?['iceServers'];
      if (list is List && list.isNotEmpty) {
        return [
          for (final s in list)
            if (s is Map) Map<String, dynamic>.from(s),
        ];
      }
    } catch (_) {}
    return [
      {
        'urls': ['stun:stun.l.google.com:19302'],
      },
    ];
  }

  /// Opens the microphone (and camera), connects to the partner.
  Future<void> join() async {
    await _requestPermissions();
    _checkAlive();

    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
    _checkAlive();

    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 720},
              'height': {'ideal': 1280},
              'frameRate': {'ideal': 24},
            }
          : false,
    });
    _localStream = stream;
    if (_disposed) {
      await _stopLocal();
      _checkAlive();
    }
    if (video) localRenderer.srcObject = stream;

    final pc = await createPeerConnection({
      'iceServers': await _iceServers(),
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
    });
    _pc = pc;
    if (_disposed) {
      await _teardown();
      _checkAlive();
    }

    for (final track in stream.getTracks()) {
      await pc.addTrack(track, stream);
    }

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      _outgoingCandidates.add({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
      // Batched: one write carries every candidate found in ~150 ms.
      _candidateFlush ??= Timer(const Duration(milliseconds: 150), _flush);
    };

    pc.onTrack = (event) {
      if (event.streams.isEmpty) return;
      remoteRenderer.srcObject = event.streams.first;
      if (event.track.kind == 'video') hasRemoteVideo = true;
      _notify();
    };

    pc.onConnectionState = (state) {
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          remoteConnected = true;
          partnerHasJoined = true;
          _restartTimer?.cancel();
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          remoteConnected = false;
          // Often recovers by itself (network switch); if not, restart ICE.
          _restartTimer?.cancel();
          _restartTimer = Timer(const Duration(seconds: 4), _restartIce);
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          remoteConnected = false;
          unawaited(_restartIce());
        default:
          break;
      }
      _notify();
    };

    // Voice calls start on the earpiece, video calls on the speaker.
    speakerOn = video;
    try {
      await Helper.setSpeakerphoneOn(speakerOn);
    } catch (_) {}

    _signalSub = _signaling
        .watch(coupleId: coupleId, callId: callId, to: myUid)
        .listen((signals) => unawaited(_onSignals(signals)));

    if (isCaller) await _sendOffer();
    _notify();
  }

  Future<void> _sendOffer({bool iceRestart = false}) async {
    final pc = _pc;
    if (pc == null || _disposed) return;
    final offer = await pc.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': video,
      if (iceRestart) 'iceRestart': true,
    });
    await pc.setLocalDescription(offer);
    await _signaling.send(
      coupleId: coupleId,
      callId: callId,
      from: myUid,
      to: partnerUid,
      kind: 'offer',
      payload: {'type': offer.type, 'sdp': offer.sdp},
    );
  }

  /// Only the caller restarts, so the two phones never offer at once.
  Future<void> _restartIce() async {
    if (_disposed || remoteConnected || !isCaller) return;
    try {
      await _sendOffer(iceRestart: true);
    } catch (_) {}
  }

  Future<void> _onSignals(List<CallSignal> signals) async {
    for (final s in signals) {
      if (_disposed) return;
      if (!_handled.add(s.id) || s.from != partnerUid) continue;
      try {
        await _handle(s);
      } catch (e) {
        debugPrint('Call signal ${s.kind} failed: $e');
      }
    }
  }

  Future<void> _handle(CallSignal s) async {
    final pc = _pc;
    if (pc == null) return;
    switch (s.kind) {
      case 'offer' when !isCaller:
        await pc.setRemoteDescription(
          RTCSessionDescription(
            s.payload['sdp'] as String?,
            s.payload['type'] as String?,
          ),
        );
        _remoteDescriptionSet = true;
        await _drainCandidates();
        final answer = await pc.createAnswer({});
        await pc.setLocalDescription(answer);
        await _signaling.send(
          coupleId: coupleId,
          callId: callId,
          from: myUid,
          to: partnerUid,
          kind: 'answer',
          payload: {'type': answer.type, 'sdp': answer.sdp},
        );
      case 'answer' when isCaller:
        await pc.setRemoteDescription(
          RTCSessionDescription(
            s.payload['sdp'] as String?,
            s.payload['type'] as String?,
          ),
        );
        _remoteDescriptionSet = true;
        await _drainCandidates();
      case 'candidates':
        final list = s.payload['candidates'];
        if (list is! List) return;
        for (final c in list) {
          if (c is! Map) continue;
          final candidate = RTCIceCandidate(
            c['candidate'] as String?,
            c['sdpMid'] as String?,
            (c['sdpMLineIndex'] as num?)?.toInt(),
          );
          if (_remoteDescriptionSet) {
            await pc.addCandidate(candidate);
          } else {
            _pendingRemoteCandidates.add(candidate);
          }
        }
    }
  }

  Future<void> _drainCandidates() async {
    final pc = _pc;
    if (pc == null) return;
    final pending = List.of(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final c in pending) {
      try {
        await pc.addCandidate(c);
      } catch (_) {}
    }
  }

  Future<void> _flush() async {
    _candidateFlush = null;
    if (_outgoingCandidates.isEmpty || _disposed) return;
    final batch = List.of(_outgoingCandidates);
    _outgoingCandidates.clear();
    try {
      await _signaling.send(
        coupleId: coupleId,
        callId: callId,
        from: myUid,
        to: partnerUid,
        kind: 'candidates',
        payload: {'candidates': batch},
      );
    } catch (e) {
      debugPrint('Could not send call candidates: $e');
    }
  }

  // ---- Controls ----------------------------------------------------------

  Future<void> toggleMic() async {
    final stream = _localStream;
    if (stream == null) return;
    micMuted = !micMuted;
    for (final t in stream.getAudioTracks()) {
      t.enabled = !micMuted;
    }
    _notify();
  }

  Future<void> toggleCamera() async {
    final stream = _localStream;
    if (stream == null) return;
    cameraOff = !cameraOff;
    for (final t in stream.getVideoTracks()) {
      t.enabled = !cameraOff;
    }
    _notify();
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? const [];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (_) {}
  }

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    try {
      await Helper.setSpeakerphoneOn(speakerOn);
    } catch (_) {}
    _notify();
  }

  // ---- Teardown ------------------------------------------------------------

  Future<void> _stopLocal() async {
    final stream = _localStream;
    _localStream = null;
    if (stream == null) return;
    for (final t in stream.getTracks()) {
      try {
        await t.stop();
      } catch (_) {}
    }
    try {
      await stream.dispose();
    } catch (_) {}
  }

  Future<void> _teardown() async {
    _candidateFlush?.cancel();
    _restartTimer?.cancel();
    await _signalSub?.cancel();
    _signalSub = null;
    final pc = _pc;
    _pc = null;
    if (pc != null) {
      try {
        await pc.close();
        await pc.dispose();
      } catch (_) {}
    }
    await _stopLocal();
    if (_renderersReady) {
      _renderersReady = false;
      try {
        localRenderer.srcObject = null;
        remoteRenderer.srcObject = null;
        await localRenderer.dispose();
        await remoteRenderer.dispose();
      } catch (_) {}
    }
    remoteConnected = false;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_teardown());
    super.dispose();
  }
}
