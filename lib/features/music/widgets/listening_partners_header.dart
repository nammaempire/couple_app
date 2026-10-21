import 'package:flutter/material.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/avatar/widgets/profile_avatar.dart';

/// You and your partner side by side, each with a green dot while their
/// phone is on the player, and a line saying whether they've joined.
class ListeningPartnersHeader extends StatelessWidget {
  const ListeningPartnersHeader({
    super.key,
    required this.me,
    required this.partner,
    required this.partnerName,
    required this.meListening,
    required this.partnerListening,
    this.doing = 'listening',
  });

  /// "listening" or "watching".
  final String doing;

  final AppUser? me;
  final AppUser? partner;
  final String partnerName;
  final bool meListening;
  final bool partnerListening;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget avatar(AppUser? user, String name, bool listening) => Stack(
      clipBehavior: Clip.none,
      children: [
        ProfileAvatar(user: user, size: 44, fallbackName: name),
        if (listening)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF34C759),
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 2),
              ),
            ),
          ),
      ],
    );

    return Row(
      children: [
        SizedBox(
          width: 76,
          height: 44,
          child: Stack(
            children: [
              avatar(partner, partnerName, partnerListening),
              Positioned(
                left: 32,
                child: avatar(me, me?.displayName ?? 'You', meListening),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            partnerListening
                ? '$partnerName is $doing with you'
                : 'Waiting for $partnerName to join — they’ll see a banner',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: partnerListening
                  ? scheme.onSurface
                  : scheme.onSurfaceVariant,
              fontWeight: partnerListening ? FontWeight.w600 : null,
            ),
          ),
        ),
      ],
    );
  }
}
