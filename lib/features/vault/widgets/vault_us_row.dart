import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/couple/providers/separation_providers.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';
import 'package:couple_app/features/vault/providers/vault_providers.dart';
import 'package:couple_app/features/vault/screens/vault_screen.dart';

/// The discreet "🔒 Private" row on the Us tab. A gold dot appears when the
/// partner's side has an alert. Opens the vault (or its setup); closed
/// while the pairing is ending.
class VaultUsRow extends ConsumerWidget {
  const VaultUsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paired = ref.watch(
      coupleProvider.select((c) => c.value?.isComplete ?? false),
    );
    // Closed for both while the pairing ends (the rules refuse it too).
    final closed = ref.watch(separationActiveProvider);
    final open = paired && !closed;
    final alerts = open ? ref.watch(vaultAlertsProvider) : const [];
    final b = Theme.of(context).brightness;
    const preset = GradientPreset.night;

    return GradientGroup(
      preset: preset,
      children: [
        ListTile(
          leading: const Text('🔒', style: TextStyle(fontSize: 22)),
          title: const Text(
            'Private',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            closed
                ? 'Private is closed while your pairing ends'
                : paired
                ? 'Only for the two of you'
                : 'Opens once your partner joins',
          ),
          // Closed still reads clearly; it just doesn't open.
          enabled: paired,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (alerts.isNotEmpty)
                Semantics(
                  label: 'New vault alert',
                  child: Container(
                    key: const Key('vault-alert-dot'),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: preset.accent(b),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: preset.accent(b).withValues(alpha: .6),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Icon(closed ? Icons.lock_outline : Icons.chevron_right),
            ],
          ),
          onTap: open
              ? () => Navigator.of(context).push(VaultScreen.route())
              : null,
        ),
      ],
    );
  }
}
