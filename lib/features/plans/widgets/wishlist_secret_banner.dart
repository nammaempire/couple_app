import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';

/// A reassuring note at the top of the partner's wishlist: your claims are
/// secret. Night-sky gradient with twinkling stars.
class WishlistSecretBanner extends StatelessWidget {
  const WishlistSecretBanner({super.key, required this.partnerName});

  final String partnerName;

  static const preset = GradientPreset.night;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: AnimatedGradientCard(
        preset: preset,
        radius: 22,
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            const Positioned.fill(
              child: RepaintBoundary(
                child: FloatingHearts(
                  count: 10,
                  seed: 5,
                  style: ParticleStyle.stars,
                  opacity: .6,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: .14),
                    ),
                    child: Icon(Icons.lock_outline, color: preset.accent(b)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tap "I\'ll get this" to quietly call dibs. $partnerName '
                      'won\'t see what you\'re getting.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: preset.foreground(b),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
