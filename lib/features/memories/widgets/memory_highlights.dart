import 'package:flutter/material.dart';

import 'package:couple_app/features/memories/models/memory.dart';
import 'package:couple_app/features/memories/widgets/memory_banner_card.dart';

/// "On this day" and the monthly recap entry, above the timeline.
class MemoryHighlights extends StatelessWidget {
  const MemoryHighlights({
    super.key,
    required this.all,
    required this.onOpenRecap,
    required this.onOpenMemory,
  });

  final List<Memory> all;
  final VoidCallback onOpenRecap;
  final ValueChanged<Memory> onOpenMemory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final onThisDay = MemoryRecap.onThisDay(all, now);
    final thisMonth = MemoryRecap.month(all, now.year, now.month);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        children: [
          if (onThisDay.isNotEmpty)
            MemoryBannerCard(
              imageUrl: onThisDay.first.coverUrl,
              eyebrow: 'ON THIS DAY',
              title: onThisDay.first.title,
              subtitle: _yearsAgo(now.year - onThisDay.first.date.year),
              onTap: () => onOpenMemory(onThisDay.first),
            ),
          if (onThisDay.isNotEmpty) const SizedBox(height: 10),
          Material(
            color: theme.colorScheme.primaryContainer.withValues(alpha: .6),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: onOpenRecap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Our Memories recap',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            thisMonth.isEmpty
                                ? 'Look back at any month or year'
                                : '${thisMonth.memories.length} so far in '
                                      '${thisMonth.label}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _yearsAgo(int years) =>
      years == 1 ? '1 year ago today' : '$years years ago today';
}
