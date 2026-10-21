import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';

/// Tappable card offering one of the pairing paths (create or join), on a
/// drifting gradient.
class PairingChoiceCard extends StatelessWidget {
  const PairingChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    this.preset = GradientPreset.blush,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;
  final GradientPreset preset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    return AnimatedGradientCard(
      preset: preset,
      onTap: onTap,
      radius: 26,
      padding: const EdgeInsets.fromLTRB(16, 18, 12, 18),
      child: Row(
        children: [
          IconTile(icon: icon, preset: preset, size: 52),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: romanceSerif(theme.textTheme.titleLarge).copyWith(
                    fontWeight: FontWeight.w700,
                    color: preset.foreground(b),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: preset.foregroundMuted(b),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: preset.foregroundMuted(b)),
        ],
      ),
    );
  }
}
