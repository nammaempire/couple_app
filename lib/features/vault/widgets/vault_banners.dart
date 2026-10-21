import 'package:flutter/material.dart';

import 'package:couple_app/features/vault/models/vault_event.dart';
import 'package:couple_app/features/vault/models/vault_meta.dart';
import 'package:couple_app/features/vault/widgets/vault_look.dart';

/// "Approve Ravi's phone (Pixel 8)?" with the phone's safety code, on an
/// open vault.
class VaultApproveBanner extends StatelessWidget {
  const VaultApproveBanner({
    super.key,
    required this.device,
    required this.owner,
    required this.onApprove,
    required this.onLater,
    this.busy = false,
  });

  final VaultDevice device;

  /// "Ravi's" or "your".
  final String owner;
  final VoidCallback? onApprove;
  final VoidCallback onLater;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return VaultCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.phone_android, color: vaultGold, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Approve $owner phone (${device.name})?',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Check that phone shows the same safety code:',
            style: theme.textTheme.bodySmall?.copyWith(color: vaultMuted),
          ),
          const SizedBox(height: 4),
          Text(
            device.fingerprint,
            key: const Key('vault-approve-fingerprint'),
            style: const TextStyle(
              color: vaultGold,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.6,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onLater,
                style: TextButton.styleFrom(foregroundColor: vaultMuted),
                child: const Text('Not now'),
              ),
              const SizedBox(width: 6),
              FilledButton(
                style: vaultButtonStyle(
                  context,
                  minimumSize: const Size(110, 42),
                ),
                onPressed: busy ? null : onApprove,
                child: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Approve'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One alert from the partner's side, dismissible.
class VaultAlertBanner extends StatelessWidget {
  const VaultAlertBanner({
    super.key,
    required this.event,
    required this.partnerName,
    required this.onDismiss,
  });

  final VaultEvent event;
  final String partnerName;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final warning = event.isWarning;
    return VaultCard(
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
      child: Row(
        children: [
          Icon(
            warning ? Icons.warning_amber_rounded : Icons.info_outline,
            color: warning ? vaultBlush : vaultGold,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              event.describe(partnerName),
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: vaultMuted),
            tooltip: 'Dismiss',
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// Encrypting and sending a photo.
class VaultProgressBanner extends StatelessWidget {
  const VaultProgressBanner({super.key, required this.label, this.progress});

  final String label;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    return VaultCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p == null ? label : '$label ${(p * 100).round()}%',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: p,
              minHeight: 5,
              color: vaultGold,
              backgroundColor: Colors.white12,
            ),
          ),
        ],
      ),
    );
  }
}
