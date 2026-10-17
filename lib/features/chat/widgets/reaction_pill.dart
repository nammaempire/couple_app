import 'package:flutter/material.dart';

/// The small floating cluster of emoji beneath a reacted-to message.
class ReactionPill extends StatelessWidget {
  const ReactionPill({super.key, required this.emoji});

  final List<String> emoji;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withValues(alpha: .4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(emoji.join(' '), style: const TextStyle(fontSize: 12)),
    );
  }
}
