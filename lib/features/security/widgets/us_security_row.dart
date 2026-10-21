import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/security/providers/security_providers.dart';
import 'package:couple_app/features/security/screens/security_screen.dart';

/// "Sign-in protection" for the Account group on the Us tab: how many
/// phones can open the account and whether a recovery email is set, with a
/// dot for unread notices. Opens [SecurityScreen].
///
/// A plain [ListTile], so it takes the group's colours.
class UsSecurityRow extends ConsumerWidget {
  const UsSecurityRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phones = ref.watch(knownDevicesProvider).value?.length;
    final reauth = ref.watch(reauthOptionsProvider);
    final notices = ref.watch(securityNoticesProvider);
    final b = Theme.of(context).brightness;

    final parts = [
      if (phones != null) phones == 1 ? '1 phone' : '$phones phones',
      reauth.any ? 'recovery email on' : 'add a recovery email',
    ];
    final subtitle = parts.join(' · ');

    return ListTile(
      key: const Key('us-security-row'),
      leading: const Icon(Icons.verified_user_outlined),
      title: const Text('Sign-in protection'),
      subtitle: Text(subtitle[0].toUpperCase() + subtitle.substring(1)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (notices.isNotEmpty)
            Semantics(
              label: 'New security notice',
              child: Container(
                key: const Key('us-security-dot'),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: GradientPreset.ocean.accent(b),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => Navigator.of(context).push(SecurityScreen.route()),
    );
  }
}
