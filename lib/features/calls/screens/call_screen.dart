import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/services/voice_playback.dart';
import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/calls/data/webrtc_call_engine.dart';
import 'package:couple_app/features/calls/data/call_service.dart';
import 'package:couple_app/features/calls/models/call_session.dart';
import 'package:couple_app/features/calls/providers/call_providers.dart';
import 'package:couple_app/features/calls/widgets/call_avatar_backdrop.dart';
import 'package:couple_app/features/calls/widgets/call_controls.dart';
import 'package:couple_app/features/calls/widgets/local_video_preview.dart';
import 'package:couple_app/features/calls/widgets/remote_video_view.dart';
import 'package:couple_app/features/chat/data/chat_service.dart';
import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/providers/chat_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';

/// The in-call screen, for both the caller and the callee.
///
/// It owns the WebRTC call engine for the duration of the call and watches the
/// signalling document so a hang-up on either side closes both screens.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({
    super.key,
    required this.session,
    required this.isOutgoing,
  });

  final CallSession session;

  /// True when this user placed the call and is waiting for an answer.
  final bool isOutgoing;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  late final WebRtcCallEngine _engine;

  // Read once in initState: dispose() logs the call, and ref can no longer
  // be used there.
  late final String _coupleId;
  late final String _myUid;
  late final CallService _calls;
  late final ChatService _chat;

  StreamSubscription<CallSession?>? _callSub;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  bool _joining = false;
  bool _hasJoined = false;
  String? _error;

  /// Set once this screen starts closing, so the back-button handler does
  /// not treat our own pop as a hang-up.
  bool _closing = false;

  /// Caller side: gives up when nobody answers in time.
  Timer? _ringTimer;

  /// When the call connected, for the talk time in the call log.
  DateTime? _acceptedAt;

  /// How the call ended, as last seen on the signalling document.
  CallStatus? _finalStatus;

  bool _logged = false;

  @override
  void initState() {
    super.initState();
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
    _calls = ref.read(callServiceProvider);
    _chat = ref.read(chatServiceProvider);
    VoicePlayback.instance.stop();
    final session = widget.session;
    _engine = WebRtcCallEngine(
      coupleId: _coupleId,
      callId: session.channelName,
      myUid: _myUid,
      partnerUid: session.callerId == _myUid
          ? session.calleeId
          : session.callerId,
      isCaller: widget.isOutgoing,
      video: session.isVideo,
    );
    _engine.addListener(_onEngineChanged);
    _watchSignalling();

    if (widget.session.isActive) {
      // The callee already accepted before this screen opened, so connect
      // and start the timer now.
      _acceptedAt = DateTime.now();
      _startTicker();
      _connect();
    } else if (widget.isOutgoing) {
      // The caller waits for the accept, but not forever.
      _ringTimer = Timer(CallSession.ringTimeout, _onRingTimeout);
    }
  }

  @override
  void dispose() {
    _logCall();
    _ringTimer?.cancel();
    _callSub?.cancel();
    _ticker?.cancel();
    _engine.removeListener(_onEngineChanged);
    _engine.dispose();
    super.dispose();
  }

  void _onEngineChanged() {
    if (mounted) setState(() {});
  }

  void _watchSignalling() {
    _callSub = _calls.watchCall(_coupleId).listen((session) {
      if (!mounted) return;

      // The other side hung up, declined, it rang out, or the document
      // was cleared.
      if (session == null || session.isFinished) {
        _finalStatus = session?.status;
        _close(
          message: switch (session?.status) {
            CallStatus.declined => '${ref.read(partnerNameProvider)} declined',
            CallStatus.missed when widget.isOutgoing => 'No answer',
            _ => null,
          },
        );
        return;
      }

      // Caller side: the callee just accepted, so connect.
      if (session.isActive && !_hasJoined && !_joining) {
        _ringTimer?.cancel();
        _acceptedAt ??= DateTime.now();
        _startTicker();
        _connect();
      }
    });
  }

  Future<void> _onRingTimeout() async {
    if (_acceptedAt != null || _closing) return;
    try {
      // The signalling listener closes the screen once this lands.
      await _calls.markMissed(_coupleId);
    } catch (_) {
      _finalStatus = CallStatus.missed;
      _close(message: 'No answer');
    }
  }

  /// The caller records the call in the chat once, however it ended.
  void _logCall() {
    if (!widget.isOutgoing || _logged) return;
    _logged = true;

    final acceptedAt = _acceptedAt;
    final CallOutcome outcome;
    if (acceptedAt != null) {
      outcome = CallOutcome.completed;
    } else if (_finalStatus == CallStatus.declined) {
      outcome = CallOutcome.declined;
    } else {
      outcome = CallOutcome.missed;
    }

    _chat
        .logCall(
          coupleId: _coupleId,
          callerId: _myUid,
          video: widget.session.isVideo,
          outcome: outcome,
          talkTime: acceptedAt == null
              ? null
              : DateTime.now().difference(acceptedAt),
        )
        .catchError((_) {});
  }

  /// Times the call from this phone's own clock, so a phone whose clock
  /// disagrees with the server never shows a negative duration.
  void _startTicker() {
    _ticker?.cancel();
    final from = _acceptedAt ?? DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(from);
      setState(() => _elapsed = elapsed.isNegative ? Duration.zero : elapsed);
    });
  }

  Future<void> _connect() async {
    if (_joining || _hasJoined) return;
    setState(() => _joining = true);

    try {
      await _engine.join();
      if (mounted) setState(() => _hasJoined = true);
    } on CallSetupException catch (e) {
      if (mounted) setState(() => _error = e.message);
      await _calls.endCall(_coupleId);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not connect the call.');
      await _calls.endCall(_coupleId);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _hangUp() async {
    if (_closing) return;
    _finalStatus ??= CallStatus.ended;
    try {
      await _calls.endCall(_coupleId);
    } catch (_) {
      // Close locally even if the network write failed.
    }
    _close();
  }

  void _close({String? message}) {
    if (!mounted || _closing) return;
    _closing = true;
    _ticker?.cancel();
    _ringTimer?.cancel();
    _logCall();
    // A direct pop: maybePop would be blocked by this screen's PopScope and
    // re-enter the hang-up handler.
    Navigator.of(context).pop();
    if (message != null) context.showSnackMessage(message);
  }

  String get _statusLabel {
    if (_error != null) return 'Call failed';
    if (!_hasJoined) {
      return widget.isOutgoing ? 'Ringing…' : 'Connecting…';
    }
    if (!_engine.remoteConnected) {
      return _engine.partnerHasJoined ? 'Reconnecting…' : 'Connecting…';
    }
    return _formatDuration(_elapsed);
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final partnerName = ref.watch(partnerNameProvider);
    final isVideo = widget.session.isVideo;
    final connected = _engine.remoteConnected;

    return PopScope(
      // Leaving by back-swipe should hang up, not silently orphan the call.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_closing) _hangUp();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF14100F),
        body: Stack(
          children: [
            if (isVideo && connected)
              RemoteVideoView(engine: _engine)
            else
              CallAvatarBackdrop(name: partnerName, pulse: !connected),

            if (isVideo && _hasJoined && !_engine.cameraOff)
              Positioned(
                top: 60,
                right: 16,
                width: 110,
                height: 160,
                child: LocalVideoPreview(engine: _engine),
              ),

            Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Padding(
                    // Clear of the local preview in the corner.
                    padding: EdgeInsets.symmetric(
                      horizontal: isVideo && _hasJoined ? 132 : 24,
                    ),
                    child: Text(
                      partnerName,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        shadows: [
                          Shadow(color: Color(0x66000000), blurRadius: 12),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  GlassPanel(
                    dark: true,
                    radius: 30,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _error != null
                                ? const Color(0xFFFF8A8A)
                                : connected
                                ? const Color(0xFF6EE7A0)
                                : const Color(0xFFFFC27A),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _statusLabel,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .92),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFFFB4B4),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            Positioned(
              left: 0,
              right: 0,
              bottom: 48,
              child: CallControls(
                engine: _engine,
                isVideo: isVideo,
                onHangUp: _hangUp,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
