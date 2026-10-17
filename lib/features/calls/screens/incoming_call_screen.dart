import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/services/voice_playback.dart';
import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/calls/data/call_service.dart';
import 'package:couple_app/features/calls/models/call_session.dart';
import 'package:couple_app/features/calls/providers/call_providers.dart';
import 'package:couple_app/features/calls/screens/call_screen.dart';
import 'package:couple_app/features/calls/widgets/call_backdrop.dart';
import 'package:couple_app/features/calls/widgets/partner_initial_avatar.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';

/// Full-screen incoming call, with accept and decline.
///
/// Pulses haptics while ringing, since without push notifications this only
/// appears when the app is already open.
class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({super.key, required this.session});

  final CallSession session;

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen> {
  late final String _coupleId;
  late final CallService _calls;

  StreamSubscription<CallSession?>? _callSub;
  Timer? _buzzTimer;
  bool _answering = false;

  /// Set once this screen starts closing, so the back-button handler does
  /// not turn our own pop into a decline.
  bool _closing = false;

  /// The latest signalling state, so a failed accept can tell whether the
  /// caller hung up in the meantime.
  CallSession? _latest;

  @override
  void initState() {
    super.initState();
    _coupleId = ref.read(currentCoupleIdProvider);
    _calls = ref.read(callServiceProvider);
    VoicePlayback.instance.stop();
    _latest = widget.session;
    _startBuzzing();

    // If the caller gives up, close this screen rather than ringing forever.
    _callSub = _calls.watchCall(_coupleId).listen((session) {
      if (!mounted) return;
      _latest = session;
      if (session == null || session.isFinished || !session.isRinging) {
        if (!_answering) _dismiss();
      }
    });
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _buzzTimer?.cancel();
    super.dispose();
  }

  void _startBuzzing() {
    HapticFeedback.heavyImpact();
    _buzzTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      HapticFeedback.heavyImpact();
    });
  }

  void _dismiss() {
    _buzzTimer?.cancel();
    if (!mounted || _closing) return;
    _closing = true;
    // A direct pop: maybePop would be blocked by this screen's PopScope and
    // re-enter the decline handler, overwriting the caller's hang-up.
    Navigator.of(context).pop();
  }

  Future<void> _accept() async {
    setState(() => _answering = true);
    _buzzTimer?.cancel();

    final bool accepted;
    try {
      accepted = await _calls.acceptCall(_coupleId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _answering = false);
      // The hang-up may have arrived while we were answering, when the
      // listener deliberately ignored it.
      final latest = _latest;
      if (latest == null || !latest.isRinging) {
        _dismiss();
        return;
      }
      _startBuzzing();
      context.showSnackMessage('Could not answer. Check your connection.');
      return;
    }
    if (!mounted) return;
    if (!accepted) {
      context.showSnackMessage('${ref.read(partnerNameProvider)} hung up');
      _dismiss();
      return;
    }

    // Replace this screen so back does not land on a stale ringing view.
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          session: CallSession(
            callerId: widget.session.callerId,
            calleeId: widget.session.calleeId,
            type: widget.session.type,
            status: CallStatus.accepted,
            channelName: widget.session.channelName,
            startedAt: widget.session.startedAt,
            answeredAt: DateTime.now(),
          ),
          isOutgoing: false,
        ),
      ),
    );
  }

  Future<void> _decline() async {
    if (_closing || _answering) return;
    _buzzTimer?.cancel();
    try {
      await _calls.declineCall(_coupleId);
    } catch (_) {
      // Dismiss locally even if the network write failed.
    }
    _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final partnerName = ref.watch(partnerNameProvider);
    final isVideo = widget.session.isVideo;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_closing) _decline();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF14100F),
        body: CallBackdrop(
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),

                PartnerInitialAvatar(
                  name: partnerName,
                  size: 128,
                  fontSize: 50,
                ),
                const SizedBox(height: 24),

                Text(
                  partnerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isVideo ? Icons.videocam : Icons.call,
                      size: 16,
                      color: Colors.white.withValues(alpha: .7),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isVideo ? 'Incoming video call' : 'Incoming voice call',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .7),
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),

                const Spacer(flex: 3),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _AnswerButton(
                        icon: Icons.call_end,
                        label: 'Decline',
                        color: const Color(0xFFE23D50),
                        onPressed: _answering ? null : _decline,
                      ),
                      _AnswerButton(
                        icon: isVideo ? Icons.videocam : Icons.call,
                        label: 'Accept',
                        color: const Color(0xFF3BBF6B),
                        onPressed: _answering ? null : _accept,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 56),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .8),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
