import 'package:flutter/material.dart';

import 'package:couple_app/features/home/models/mood.dart';
import 'package:couple_app/features/home/widgets/mood_picker_sheet.dart';

/// Shows both partners' moods and lets this user set their own.
class MoodCard extends StatelessWidget {
  const MoodCard({
    super.key,
    required this.myUid,
    required this.partnerUid,
    required this.partnerName,
    required this.moods,
    required this.onPick,
  });

  final String myUid;
  final String? partnerUid;
  final String partnerName;
  final Map<String, MoodEntry> moods;
  final void Function(Mood mood, String note) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = moods[myUid];
    final theirs = partnerUid == null ? null : moods[partnerUid];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How you\'re both doing', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MoodSlot(
                  label: 'You',
                  entry: mine,
                  emptyHint: 'Tap to set',
                  onTap: () => _openPicker(context, mine),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MoodSlot(
                  label: partnerName,
                  entry: theirs,
                  emptyHint: partnerUid == null
                      ? 'Not paired yet'
                      : 'Nothing yet today',
                  onTap: null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openPicker(BuildContext context, MoodEntry? current) async {
    final result = await showModalBottomSheet<({Mood mood, String note})>(
      context: context,
      isScrollControlled: true,
      builder: (context) => MoodPickerSheet(current: current),
    );
    if (result != null) onPick(result.mood, result.note);
  }
}

class _MoodSlot extends StatelessWidget {
  const _MoodSlot({
    required this.label,
    required this.entry,
    required this.emptyHint,
    required this.onTap,
  });

  final String label;
  final MoodEntry? entry;
  final String emptyHint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mood = entry?.mood;
    final isStale = entry != null && !entry!.isFresh;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: mood == null
              ? theme.colorScheme.surface
              : mood.color.withValues(alpha: isStale ? .12 : .28),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Text(
              mood?.emoji ?? '➕',
              style: TextStyle(
                fontSize: 30,
                color: mood == null ? theme.colorScheme.onSurfaceVariant : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              mood?.label ?? emptyHint,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (entry != null && entry!.note.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                entry!.note,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (isStale) ...[
              const SizedBox(height: 4),
              Text(
                'earlier',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: .7,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
