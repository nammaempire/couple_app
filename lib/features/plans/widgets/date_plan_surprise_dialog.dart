import 'package:flutter/material.dart';

import 'package:couple_app/features/plans/models/date_plan.dart';
import 'package:couple_app/features/plans/widgets/date_plan_card.dart';

/// What to do with the surprise pick.
enum DatePlanSurpriseChoice { plan, again }

/// Shows the idea "Surprise me" picked. Pops with a
/// [DatePlanSurpriseChoice], or null when closed.
class DatePlanSurpriseDialog extends StatelessWidget {
  const DatePlanSurpriseDialog({
    super.key,
    required this.plan,
    required this.canPickAgain,
  });

  final DatePlan plan;
  final bool canPickAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = plan.location.trim();
    return AlertDialog(
      icon: TweenAnimationBuilder<double>(
        tween: Tween(begin: .4, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.elasticOut,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Container(
          width: 84,
          height: 84,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: DatePlanLook.presetFor(
                plan.vibe,
              ).colors(theme.brightness),
            ),
          ),
          child: Text(plan.vibe.emoji, style: const TextStyle(fontSize: 42)),
        ),
      ),
      title: Text(
        plan.title.isEmpty ? 'Untitled date' : plan.title,
        textAlign: TextAlign.center,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'How about this one?',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (location.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Flexible(child: Text(location, textAlign: TextAlign.center)),
              ],
            ),
          ],
        ],
      ),
      actions: [
        if (canPickAgain)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, DatePlanSurpriseChoice.again),
            child: const Text('Pick another'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context, DatePlanSurpriseChoice.plan),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 40),
            shape: const StadiumBorder(),
          ),
          child: const Text('Plan it'),
        ),
      ],
    );
  }
}
