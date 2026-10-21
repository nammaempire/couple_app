import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';

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

    final b = theme.brightness;
    const recapPreset = GradientPreset.lavender;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        children: [
          if (onThisDay.isNotEmpty)
            EntranceAnimation(
              child: MemoryBannerCard(
                imageUrl: onThisDay.first.coverUrl,
                eyebrow: 'ON THIS DAY',
                title: onThisDay.first.title,
                subtitle: _yearsAgo(now.year - onThisDay.first.date.year),
                emoji: MemoryAlbums.emojiFor(onThisDay.first.album),
                onTap: () => onOpenMemory(onThisDay.first),
              ),
            ),
          if (onThisDay.isNotEmpty) const SizedBox(height: 12),
          EntranceAnimation(
            index: 1,
            child: AnimatedGradientCard(
              preset: recapPreset,
              onTap: onOpenRecap,
              radius: 22,
              sheen: false,
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: recapPreset.isDarkIn(b) ? .12 : .65,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      color: recapPreset.accent(b),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Our Memories recap',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: recapPreset.foreground(b),
                          ),
                        ),
                        Text(
                          thisMonth.isEmpty
                              ? 'Look back at any month or year'
                              : '${thisMonth.memories.length} so far in '
                                    '${thisMonth.label}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: recapPreset.foregroundMuted(b),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: recapPreset.foregroundMuted(b),
                  ),
                ],
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
