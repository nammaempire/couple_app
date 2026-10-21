import 'package:flutter/material.dart';

import 'package:couple_app/features/calls/widgets/call_avatar_ring.dart';
import 'package:couple_app/features/calls/widgets/call_backdrop.dart';
import 'package:couple_app/features/calls/widgets/partner_initial_avatar.dart';

/// Shown for voice calls, and for video before the far side connects.
class CallAvatarBackdrop extends StatelessWidget {
  const CallAvatarBackdrop({super.key, required this.name, this.pulse = false});

  final String name;

  /// Breathe the ring while ringing or connecting.
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    return CallBackdrop(
      child: Center(
        child: CallAvatarRing(
          size: 132,
          pulse: pulse,
          child: PartnerInitialAvatar(name: name, size: 132, fontSize: 52),
        ),
      ),
    );
  }
}
