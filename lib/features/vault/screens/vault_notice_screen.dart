import 'package:flutter/material.dart';

import 'package:couple_app/features/vault/widgets/vault_look.dart';

/// A calm full-page message on the night gradient: the age check, waiting
/// for approval, or the vault being unavailable.
class VaultNoticeScreen extends StatelessWidget {
  const VaultNoticeScreen({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    this.extra,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String text;

  /// Shown under [text] (a safety code, a note).
  final Widget? extra;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Shows a spinner instead of the primary button.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return VaultBackdrop(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    VaultBadge(icon: icon),
                    const SizedBox(height: 20),
                    VaultTitle(title),
                    const SizedBox(height: 12),
                    VaultText(text),
                    if (extra != null) ...[const SizedBox(height: 20), extra!],
                    const SizedBox(height: 32),
                    if (busy)
                      const CircularProgressIndicator(color: vaultGold)
                    else if (primaryLabel != null)
                      FilledButton(
                        style: vaultButtonStyle(context),
                        onPressed: onPrimary,
                        child: Text(primaryLabel!),
                      ),
                    if (secondaryLabel != null) ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        style: vaultOutlineStyle(context),
                        onPressed: onSecondary,
                        child: Text(secondaryLabel!),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A phone's safety code in large, spaced digits.
class VaultSafetyCode extends StatelessWidget {
  const VaultSafetyCode({super.key, required this.code, this.caption});

  final String code;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return VaultCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        children: [
          Text(
            'SAFETY CODE',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: vaultMuted,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            code,
            style: const TextStyle(
              color: vaultGold,
              fontSize: 24,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 6),
            Text(
              caption!,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: vaultMuted),
            ),
          ],
        ],
      ),
    );
  }
}
