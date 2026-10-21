import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/vault/models/vault_meta.dart';
import 'package:couple_app/features/vault/providers/vault_providers.dart';
import 'package:couple_app/features/vault/vault_session.dart';
import 'package:couple_app/features/vault/widgets/vault_look.dart';

/// Every phone with access to the vault: whose it is, whether it's
/// approved, its safety code, and the fingerprint / face switch for this
/// phone.
Future<void> showVaultDevicesSheet(BuildContext context) => showVaultSheet(
  context,
  (context) => const _DevicesSheet(),
  scrollable: true,
);

class _DevicesSheet extends ConsumerWidget {
  const _DevicesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = ref.watch(vaultMetaProvider).value;
    final session = ref.watch(vaultSessionProvider);
    final notifier = ref.read(vaultSessionProvider.notifier);
    final myUid = ref.watch(currentUidProvider);
    final partner = ref.watch(partnerNameProvider);
    final thisDevice = session.identity?.deviceId;
    final devices = meta?.sortedDevices ?? const <VaultDevice>[];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            const VaultTitle('Phones', size: 24, center: false),
            const SizedBox(height: 4),
            const Text(
              'Only these phones can open Private. A new phone needs '
              'approval from one that already can.',
              style: TextStyle(color: vaultMuted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            for (final d in devices)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: VaultCard(
                  padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                  child: Row(
                    children: [
                      Icon(
                        d.approved
                            ? Icons.verified_user_outlined
                            : Icons.hourglass_top_rounded,
                        color: d.approved ? vaultGold : vaultBlush,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.id == thisDevice
                                  ? '${d.name} · this phone'
                                  : d.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${d.uid == myUid ? 'You' : partner} · '
                              '${d.approved ? 'Approved' : 'Waiting for approval'}',
                              style: const TextStyle(
                                color: vaultMuted,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              d.fingerprint,
                              style: const TextStyle(
                                color: vaultGold,
                                fontSize: 13,
                                letterSpacing: 1.2,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!d.approved && notifier.canApprove)
                        FilledButton(
                          style: vaultButtonStyle(
                            context,
                            minimumSize: const Size(90, 38),
                          ),
                          onPressed: () => notifier.approve(d),
                          child: const Text('Approve'),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Material(
              color: Colors.transparent,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: const Color(0xFF2A2140),
                activeTrackColor: vaultGold,
                secondary: const Icon(Icons.fingerprint, color: vaultGold),
                title: const Text(
                  'Fingerprint or face on this phone',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Opens Private without the code',
                  style: TextStyle(color: vaultMuted),
                ),
                value: session.biometric,
                onChanged: notifier.setBiometric,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
