import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/plans/models/date_plan.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';

/// Friendly empty state for one segment of the date planner.
class DatePlannerEmptyState extends StatelessWidget {
  const DatePlannerEmptyState({
    super.key,
    required this.status,
    required this.partnerName,
    required this.onAdd,
  });

  final DatePlanStatus status;
  final String partnerName;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final (emoji, preset, title, hint, button) = switch (status) {
      DatePlanStatus.idea => (
        '💡',
        GradientPreset.sunny,
        'No date ideas yet',
        'Jot down anything you and $partnerName might love: a new café, a '
            'sunrise walk, a cooking night.',
        'Add an idea',
      ),
      DatePlanStatus.planned => (
        '🗓️',
        GradientPreset.ocean,
        'Nothing planned yet',
        'Pick an idea and give it a date. It shows up on your calendar too.',
        'Plan a date',
      ),
      DatePlanStatus.done => (
        '💞',
        GradientPreset.blush,
        'Your first date story goes here',
        'Mark a planned date as done to keep hearts and a few words about '
            'how it went.',
        null,
      ),
    };

    return GradientEmptyState(
      emoji: emoji,
      preset: preset,
      title: title,
      text: hint,
      action: button == null
          ? null
          : FilledButton.icon(
              onPressed: onAdd,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.add),
              label: Text(button),
            ),
    );
  }
}
