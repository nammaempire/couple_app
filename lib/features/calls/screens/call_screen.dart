import 'dart:async';

import 'package:flutter/material.dart';

import 'package:couple_app/core/services/voice_playback.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/features/calls/data/active_call.dart';
import 'package:couple_app/features/calls/widgets/call_avatar_backdrop.dart';
import 'package:couple_app/features/calls/widgets/call_controls.dart';
import 'package:couple_app/features/calls/widgets/local_video_preview.dart';
import 'package:couple_app/features/calls/widgets/remote_video_view.dart';

/// The full-screen view of the call in progress ([ActiveCall]), for both the
/// caller and the callee.
///
/// Closing it (back, or the arrow at the top) does not end the call: the
/// call lives in [ActiveCall], and the "return to call" bar reopens this
/// screen. It closes by itself once the call ends.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.call});

  final ActiveCall call;

  /// Opens the call screen for [call], unless it is already showing.
  static Future<void> open(NavigatorState navigator, ActiveCall call) async {
    if (call.screenOpen || call.ended) return;
    await navigator.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => CallScreen(call: call),
      ),
    );
  }

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    VoicePlayback.instance.stop();
    widget.call.addListener(_onCallChanged);
    // Notified after this frame, so listeners don't rebuild mid-build.
    scheduleMicrotask(widget.call.screenShown);
    if (widget.call.ended) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onCallChanged());
    }
  }

  @override
  void dispose() {
    widget.call.removeListener(_onCallChanged);
    widget.call.screenHidden();
    super.dispose();
  }

  void _onCallChanged() {
    if (!mounted) return;
    final call = widget.call;
    if (call.ended && !_closing) {
      _closing = true;
      final message = call.endMessage;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      if (message != null) {
        messenger?.showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final engine = call.engine;
    final partnerName = call.partnerName;
    final isVideo = call.isVideo;
    final connected = !call.ended && engine.remoteConnected;
    final hasJoined = !call.ended && call.hasJoined;
    final error = call.error;

    // Back (button or swipe) only leaves this screen: the call keeps going
    // and the "return to call" bar brings it back.
    return Scaffold(
      backgroundColor: const Color(0xFF14100F),
      body: Stack(
        children: [
          if (isVideo && connected)
            RemoteVideoView(engine: engine)
          else
            CallAvatarBackdrop(name: partnerName, pulse: !connected),

          if (isVideo && hasJoined && !engine.cameraOff)
            Positioned(
              top: 60,
              right: 16,
              width: 110,
              height: 160,
              child: LocalVideoPreview(engine: engine),
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
                    horizontal: isVideo && hasJoined ? 132 : 24,
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
                          color: error != null
                              ? const Color(0xFFFF8A8A)
                              : connected
                              ? const Color(0xFF6EE7A0)
                              : const Color(0xFFFFC27A),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        call.statusLabel,
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
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      error,
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
              engine: engine,
              isVideo: isVideo,
              onHangUp: call.hangUp,
            ),
          ),

          // Minimise: back to the app while the call carries on.
          Positioned(
            top: 0,
            left: 4,
            child: SafeArea(
              child: IconButton(
                tooltip: 'Back to the app (the call continues)',
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white,
                  size: 34,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
