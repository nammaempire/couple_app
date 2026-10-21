import 'package:flutter/material.dart';

import 'package:couple_app/features/play/ludo/ludo_logic.dart';

/// Asks which kind of Ludo game to invite the partner to. Null when the
/// sheet is dismissed.
Future<LudoMode?> showLudoModeSheet(BuildContext context) {
  return showModalBottomSheet<LudoMode>(
    context: context,
    showDragHandle: true,
    builder: (context) => const LudoModeSheet(),
  );
}

/// Classic or Quick, before the invite is sent.
class LudoModeSheet extends StatelessWidget {
  const LudoModeSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Which Ludo?',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            for (final mode in LudoMode.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  color: scheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    key: ValueKey('ludo-mode-${mode.id}'),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Text(
                      mode == LudoMode.classic ? '👑' : '⚡',
                      style: const TextStyle(fontSize: 26),
                    ),
                    title: Text(
                      mode.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(mode.description),
                    onTap: () => Navigator.pop(context, mode),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
