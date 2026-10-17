import 'package:flutter/material.dart';

import 'package:couple_app/features/chat/models/message.dart';

/// Strip under the app bar showing the latest pinned message.
class PinnedMessageBar extends StatelessWidget {
  const PinnedMessageBar({
    super.key,
    required this.latest,
    required this.count,
    required this.onTap,
    required this.onShowAll,
  });

  final Message latest;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .6),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              Icon(Icons.push_pin, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 1 ? 'Pinned' : 'Pinned · $count',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      latest.previewText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (count > 1)
                IconButton(
                  tooltip: 'All pinned messages',
                  icon: const Icon(Icons.list),
                  onPressed: onShowAll,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
