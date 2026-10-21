import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';

/// One shared list on the Plans hub.
class PlansHubTile extends StatelessWidget {
  const PlansHubTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.summary,
    this.preset = GradientPreset.blush,
  });

  /// The tile's gradient.
  final GradientPreset preset;

  final IconData icon;
  final String title;
  final String subtitle;

  /// A short live count such as "3 coming up". Hidden when null.
  final String? summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final accent = preset.accent(theme.brightness);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedGradientCard(
        preset: preset,
        onTap: onTap,
        radius: 22,
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: dark ? .12 : .65),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (summary != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      summary!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
