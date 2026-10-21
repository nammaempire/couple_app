import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';

/// Shown when there are no memories yet, or none match the filters.
class MemoriesEmptyState extends StatelessWidget {
  const MemoriesEmptyState({
    super.key,
    required this.filtering,
    required this.onCreate,
  });

  final bool filtering;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return GradientEmptyState(
      emoji: filtering ? '🔍' : '📸',
      preset: filtering ? GradientPreset.lavender : GradientPreset.sunset,
      title: filtering ? 'No memories match' : 'Your story starts here',
      text: filtering
          ? 'Try another album, date or search.'
          : 'Add your first memory: a first date, a trip, or any '
                'moment worth keeping.',
      action: filtering
          ? null
          : FilledButton.icon(
              onPressed: onCreate,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add a memory'),
            ),
    );
  }
}
