import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/calls/data/active_call.dart';
import 'package:couple_app/features/calls/models/call_session.dart';
import 'package:couple_app/features/calls/providers/call_providers.dart';
import 'package:couple_app/features/calls/screens/call_screen.dart';
import 'package:couple_app/features/chat/providers/chat_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';

/// Places a call and opens the outgoing call screen. Used by the chat app
/// bar. The partner's phone shows the incoming screen from its own
/// signalling listener in `MainShell`.
Future<void> placeCall(
  BuildContext context,
  WidgetRef ref, {
  required CallType type,
}) async {
  // Already on a call: show it instead of starting another.
  final ongoing = ActiveCall.current.value;
  if (ongoing != null && !ongoing.ended) {
    await CallScreen.open(Navigator.of(context), ongoing);
    return;
  }

  final myUid = ref.read(currentUidProvider);
  final partnerUid = ref.read(coupleProvider).value?.partnerIdFor(myUid);
  if (partnerUid == null) {
    context.showSnackMessage('You need to be paired before you can call.');
    return;
  }

  final coupleId = ref.read(currentCoupleIdProvider);
  final calls = ref.read(callServiceProvider);
  try {
    final session = await calls.startCall(
      coupleId: coupleId,
      callerId: myUid,
      calleeId: partnerUid,
      type: type,
    );
    if (!context.mounted) return;

    final call = ActiveCall.start(
      session: session,
      isOutgoing: true,
      coupleId: coupleId,
      myUid: myUid,
      partnerName: ref.read(partnerNameProvider),
      calls: calls,
      chat: ref.read(chatServiceProvider),
    );
    await CallScreen.open(Navigator.of(context), call);
  } catch (_) {
    if (!context.mounted) return;
    context.showSnackMessage('Could not start the call.');
  }
}
