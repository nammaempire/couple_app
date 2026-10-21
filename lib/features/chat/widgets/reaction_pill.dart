import 'package:flutter/material.dart';

/// The small floating cluster of emoji beneath a reacted-to message.
class ReactionPill extends StatelessWidget {
  const ReactionPill({super.key, required this.emoji});

  final List<String> emoji;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surfaceContainerLowest,
            Color.alphaBlend(
              scheme.primaryContainer.withValues(alpha: .5),
              scheme.surfaceContainerLowest,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.primary.withValues(alpha: .18)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: .16),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(emoji.join(' '), style: const TextStyle(fontSize: 13)),
    );
  }
}
