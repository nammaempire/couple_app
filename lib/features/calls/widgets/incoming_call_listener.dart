import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/calls/data/call_service.dart';
import 'package:couple_app/features/calls/models/call_session.dart';
import 'package:couple_app/features/calls/providers/call_providers.dart';
import 'package:couple_app/features/calls/screens/incoming_call_screen.dart';
import 'package:couple_app/features/couple/providers/separation_providers.dart';

/// Watches the couple's call document and shows the incoming-call screen
/// when the partner rings this user, whatever is on screen.
///
/// While the partner is muted ([mutePartnerProvider]) their call is not
/// rung: it is ended as missed straight away, which is also how the
/// caller's phone logs it, so nothing tells them they are muted.
class IncomingCallListener extends ConsumerStatefulWidget {
  const IncomingCallListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<IncomingCallListener> createState() =>
      _IncomingCallListenerState();
}

class _IncomingCallListenerState extends ConsumerState<IncomingCallListener> {
  late final CallService _calls;
  late final String _coupleId;
  late final String _myUid;
  StreamSubscription<CallSession?>? _sub;

  /// True while an incoming-call screen is on top, so a rebuild of the
  /// stream does not push a second copy of it.
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _calls = ref.read(callServiceProvider);
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
    _sub = _calls.watchCall(_coupleId).listen(_onCall);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onCall(CallSession? session) async {
    if (!mounted || session == null) return;

    // Only the callee gets the incoming screen, and only while it is still
    // ringing and has not sat unanswered past the timeout.
    if (!session.isIncomingFor(_myUid)) return;
    if (_showing || session.hasRungOut) return;

    if (ref.read(mutePartnerProvider)) {
      unawaited(_calls.markMissed(_coupleId).catchError((_) {}));
      return;
    }

    _showing = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => IncomingCallScreen(session: session),
      ),
    );
    _showing = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
