import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/plans/models/date_plan.dart';
import 'package:couple_app/features/plans/models/date_plan_lists.dart';
import 'package:couple_app/features/plans/widgets/date_plan_card.dart';
import 'package:couple_app/features/plans/widgets/date_plan_hearts.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';

/// What the details sheet asks the planner to do.
enum DatePlanAction { plan, reschedule, markDone, moveToIdeas, edit, delete }

/// Bottom sheet with a plan's details and the actions that fit its status.
/// Pops with a [DatePlanAction].
class DatePlanDetailsSheet extends StatelessWidget {
  const DatePlanDetailsSheet({
    super.key,
    required this.plan,
    required this.now,
    required this.currency,
    required this.addedBy,
  });

  final DatePlan plan;
  final DateTime now;
  final String currency;

  /// "you" or the partner's name.
  final String addedBy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final at = plan.scheduledAt;
    final cost = plan.estimatedCostMinor;

    Widget row(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );

    void pop(DatePlanAction a) => Navigator.pop(context, a);

    final primary = switch (plan.status) {
      DatePlanStatus.idea => FilledButton.icon(
        onPressed: () => pop(DatePlanAction.plan),
        icon: const Icon(Icons.event_available_outlined),
        label: const Text('Plan it'),
      ),
      DatePlanStatus.planned => FilledButton.icon(
        onPressed: () => pop(DatePlanAction.markDone),
        icon: const Icon(Icons.favorite_outline),
        label: const Text('Mark as done'),
      ),
      DatePlanStatus.done => FilledButton.icon(
        onPressed: () => pop(DatePlanAction.edit),
        icon: const Icon(Icons.edit_note),
        label: const Text('Edit how it went'),
      ),
    };

    final preset = DatePlanLook.presetFor(plan.vibe);
    final fg = preset.foreground(theme.brightness);
    final fgMuted = preset.foregroundMuted(theme.brightness);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetGradientHeader(
              preset: DatePlanLook.presetFor(plan.vibe),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${plan.vibe.emoji}  '
                    '${plan.title.isEmpty ? 'Untitled date' : plan.title}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${plan.vibe.label} · ${plan.status == DatePlanStatus.idea ? 'Idea' : plan.status.label} · added by $addedBy',
                    style: theme.textTheme.bodySmall?.copyWith(color: fgMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (at != null && !plan.isIdea)
              row(
                Icons.event_outlined,
                '${DateFormat.yMMMMEEEEd().format(at)} · '
                '${DateFormat.jm().format(at)}'
                '${plan.isPlanned && !plan.needsRecap(now) ? '  (${DatePlanLists.countdown(at, now).toLowerCase()})' : ''}',
              ),
            if (plan.location.trim().isNotEmpty)
              row(Icons.place_outlined, plan.location.trim()),
            if (cost != null)
              row(
                Icons.account_balance_wallet_outlined,
                cost == 0
                    ? 'Free'
                    : 'About ${DatePlanCost.format(cost, currency)}',
              ),
            if (plan.notes.trim().isNotEmpty) row(Icons.notes, plan.notes),
            if (plan.isDone) ...[
              const Divider(height: 24),
              Text('How it went', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              if (plan.rating != null)
                DatePlanHearts(rating: plan.rating, size: 22),
              if (plan.reflection.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  plan.reflection.trim(),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (plan.rating == null && plan.reflection.trim().isEmpty)
                Text(
                  'No notes yet. Add a few words while it\'s fresh.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: primary),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (plan.isPlanned)
                  TextButton.icon(
                    onPressed: () => pop(DatePlanAction.reschedule),
                    icon: const Icon(Icons.schedule),
                    label: const Text('Reschedule'),
                  ),
                if (!plan.isIdea)
                  TextButton.icon(
                    onPressed: () => pop(DatePlanAction.moveToIdeas),
                    icon: const Icon(Icons.lightbulb_outline),
                    label: const Text('Back to ideas'),
                  ),
                if (!plan.isDone)
                  TextButton.icon(
                    onPressed: () => pop(DatePlanAction.edit),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                TextButton.icon(
                  onPressed: () => pop(DatePlanAction.delete),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
