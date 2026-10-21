import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';
import 'package:couple_app/features/premium/providers/premium_providers.dart';

/// Where the current purchase stands, as a soft card: buying, checking with
/// the server, "Payment received — waiting for the server to confirm",
/// thanks, or what went wrong. Nothing when idle.
///
/// [successText] words the thank-you for this screen.
class PurchaseStatusBanner extends ConsumerWidget {
  const PurchaseStatusBanner({super.key, this.successText});

  final String? successText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(purchaseControllerProvider);
    final theme = Theme.of(context);
    final b = theme.brightness;

    final (preset, icon, text, spinner) = switch (state.phase) {
      PurchasePhase.idle when state.pending > 0 => (
        GradientPreset.sunny,
        Icons.hourglass_top_rounded,
        'Payment received — waiting for the server to confirm. We\'ll keep '
            'trying.',
        false,
      ),
      PurchasePhase.idle => (null, null, null, false),
      PurchasePhase.buying => (
        GradientPreset.lavender,
        Icons.shopping_bag_outlined,
        state.message ?? 'Opening Google Play…',
        true,
      ),
      PurchasePhase.verifying => (
        GradientPreset.lavender,
        Icons.verified_outlined,
        'Confirming your purchase…',
        true,
      ),
      PurchasePhase.waitingForServer => (
        GradientPreset.sunny,
        Icons.hourglass_top_rounded,
        state.message ??
            'Payment received — waiting for the server to confirm.',
        false,
      ),
      PurchasePhase.success => (
        GradientPreset.mint,
        Icons.favorite_rounded,
        successText ?? 'Thank you! It\'s all yours.',
        false,
      ),
      PurchasePhase.failed => (
        GradientPreset.peach,
        Icons.info_outline_rounded,
        state.message ?? 'Something went wrong. Try again.',
        false,
      ),
    };
    if (preset == null || text == null) return const SizedBox.shrink();

    final accent = preset.isDarkIn(b) ? preset.accent(b) : preset.ink;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AnimatedGradientCard(
        key: const Key('purchase-status'),
        preset: preset,
        radius: 20,
        animate: false,
        sheen: false,
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            if (spinner)
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: accent,
                ),
              )
            else
              IconTile(icon: icon!, preset: preset, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: preset.foreground(b),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
            if (state.phase == PurchasePhase.success ||
                state.phase == PurchasePhase.failed)
              IconButton(
                tooltip: 'Dismiss',
                icon: Icon(Icons.close, color: preset.foregroundMuted(b)),
                onPressed: () =>
                    ref.read(purchaseControllerProvider.notifier).dismiss(),
              ),
          ],
        ),
      ),
    );
  }
}
