import 'package:flutter/material.dart';

import 'package:couple_app/core/navigation/app_navigator.dart';
import 'package:couple_app/features/calls/data/active_call.dart';
import 'package:couple_app/features/calls/screens/call_screen.dart';

/// Shows a "return to call" bar above every screen while a call is in
/// progress and its full-screen view is closed, like WhatsApp's green bar.
///
/// Tapping the bar reopens the call; the red button hangs up. When a call
/// ends while its screen is closed, the reason (declined, call lost…) shows
/// as a snack bar.
class OngoingCallOverlay extends StatefulWidget {
  const OngoingCallOverlay({super.key, required this.child});

  /// The app's navigator.
  final Widget child;

  @override
  State<OngoingCallOverlay> createState() => _OngoingCallOverlayState();
}

class _OngoingCallOverlayState extends State<OngoingCallOverlay> {
  ActiveCall? _call;

  @override
  void initState() {
    super.initState();
    ActiveCall.current.addListener(_onCurrent);
    _onCurrent();
  }

  @override
  void dispose() {
    ActiveCall.current.removeListener(_onCurrent);
    _call?.removeListener(_onCallChanged);
    super.dispose();
  }

  void _onCurrent() {
    final next = ActiveCall.current.value;
    if (identical(next, _call)) return;
    _call?.removeListener(_onCallChanged);
    _call = next;
    next?.addListener(_onCallChanged);
    if (mounted) setState(() {});
  }

  void _onCallChanged() {
    final call = _call;
    if (call == null || !mounted) return;
    if (call.ended) {
      call.removeListener(_onCallChanged);
      _call = null;
      // The call screen reports its own ending when it is open.
      final message = call.endMessage;
      if (!call.screenOpen && message != null) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(message)));
      }
    }
    setState(() {});
  }

  void _open() {
    final call = _call;
    final navigator = appNavigatorKey.currentState;
    if (call == null || navigator == null) return;
    CallScreen.open(navigator, call);
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;
    final show = call != null && !call.ended && !call.screenOpen;
    if (!show) return widget.child;

    final top = MediaQuery.paddingOf(context).top;
    return Column(
      children: [
        Material(
          color: const Color(0xFF2E7D4F),
          child: InkWell(
            onTap: _open,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, top + 6, 8, 6),
              child: Row(
                children: [
                  Icon(
                    call.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tap to return to call · ${call.partnerName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    call.statusLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Hang up',
                    visualDensity: VisualDensity.compact,
                    onPressed: call.hangUp,
                    icon: const CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(0xFFE5484D),
                      child: Icon(
                        Icons.call_end_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
