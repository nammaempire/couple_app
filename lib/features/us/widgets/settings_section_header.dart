import 'package:flutter/material.dart';

/// A small coloured heading over a group of settings, with a soft gradient
/// rule trailing off after it.
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 20, 6, 10),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1.2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: .35),
                    color.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
