import 'package:flutter/material.dart';

/// An icon and a line of text for a memory's date, place or album. Sits on
/// the detail page's glass panel in [color]; otherwise a soft pill.
class MemoryFactChip extends StatelessWidget {
  const MemoryFactChip({
    super.key,
    required this.icon,
    required this.text,
    this.color,
  });

  final IconData icon;
  final String text;

  /// Text and icon colour on a glass panel. Null draws a standalone pill.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = color;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: fg ?? theme.colorScheme.primary),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: fg,
              fontWeight: fg == null ? null : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
    if (fg != null) return row;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: row,
    );
  }
}
