import 'package:flutter/material.dart';

/// A large number over a small label, one of a row of recap totals. On the
/// recap's gradient it sits in a frosted tile.
class MemoryRecapStat extends StatelessWidget {
  const MemoryRecapStat({
    super.key,
    required this.value,
    required this.label,
    this.color,
    this.mutedColor,
    this.tile,
  });

  final int value;
  final String label;

  /// Number colour; defaults to the theme's primary.
  final Color? color;

  /// Label colour; defaults to the theme's muted text.
  final Color? mutedColor;

  /// Background of the frosted tile, if any.
  final Color? tile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$value',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: color ?? theme.colorScheme.primary,
            ),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: mutedColor ?? theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
    return Expanded(
      child: tile == null
          ? content
          : Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              decoration: BoxDecoration(
                color: tile,
                borderRadius: BorderRadius.circular(16),
              ),
              child: content,
            ),
    );
  }
}
