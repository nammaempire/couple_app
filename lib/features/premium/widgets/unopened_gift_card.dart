import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';
import 'package:couple_app/features/premium/providers/premium_providers.dart';
import 'package:couple_app/features/premium/screens/gift_reveal_screen.dart';

/// A small card on Home while a gift from the partner waits to be opened.
/// Nothing otherwise.
class UnopenedGiftCard extends ConsumerWidget {
  const UnopenedGiftCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gifts = ref.watch(unopenedGiftsProvider);
    if (gifts.isEmpty) return const SizedBox.shrink();
    final from = ref.watch(partnerNameProvider);
    final theme = Theme.of(context);
    final b = theme.brightness;
    const preset = GradientPreset.festive;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AnimatedGradientCard(
        key: const Key('home-gift-card'),
        preset: preset,
        radius: 22,
        glow: preset.accent(b),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        onTap: () =>
            Navigator.of(context).push(GiftRevealScreen.route(gifts.first)),
        child: Row(
          children: [
            const Text('🎁', style: TextStyle(fontSize: 30)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gifts.length == 1
                        ? '$from sent you a gift'
                        : '$from sent you ${gifts.length} gifts',
                    style: romanceSerif(theme.textTheme.titleMedium).copyWith(
                      fontWeight: FontWeight.w700,
                      color: preset.foreground(b),
                    ),
                  ),
                  Text(
                    'Tap to open',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: preset.foregroundMuted(b),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: preset.foregroundMuted(b)),
          ],
        ),
      ),
    );
  }
}
