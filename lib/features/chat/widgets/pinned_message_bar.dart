import 'package:flutter/material.dart';

import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/widgets/chat_chrome.dart';

/// A floating glass card under the app bar showing the latest pinned
/// message.
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: ChatGlass(
        radius: 20,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.fromLTRB(10, 8, count > 1 ? 4 : 14, 8),
              child: Row(
                children: [
                  const GradientBadge(
                    icon: Icons.push_pin,
                    size: 32,
                    iconSize: 16,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          count == 1 ? 'Pinned' : 'Pinned · $count',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          latest.previewText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
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
        ),
      ),
    );
  }
}
