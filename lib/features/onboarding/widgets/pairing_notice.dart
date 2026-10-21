import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';

/// Highlighted message shown at the top of the pairing screen.
class PairingNotice extends StatelessWidget {
  const PairingNotice({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    const preset = GradientPreset.sunny;
    return AnimatedGradientCard(
      preset: preset,
      radius: 20,
      animate: false,
      shadow: false,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: preset.accent(b)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: preset.foreground(b),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
