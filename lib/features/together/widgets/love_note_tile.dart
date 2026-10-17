import 'package:flutter/material.dart';

import 'package:couple_app/features/together/models/love_note.dart';

/// A love note in a list: emoji (or a lock while sealed), title and status.
class LoveNoteTile extends StatelessWidget {
  const LoveNoteTile({
    super.key,
    required this.note,
    required this.subtitle,
    required this.onTap,
    this.sealed = false,
    this.unread = false,
  });

  final LoveNote note;
  final String subtitle;
  final VoidCallback onTap;
  final bool sealed;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: unread
            ? scheme.primaryContainer.withValues(alpha: .7)
            : scheme.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Text(
                  sealed ? '🔒' : note.emoji,
                  style: const TextStyle(fontSize: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.envelopeTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: unread
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (note.hasVoice)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.mic_none,
                      size: 18,
                      color: scheme.primary,
                    ),
                  ),
                if (unread)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
