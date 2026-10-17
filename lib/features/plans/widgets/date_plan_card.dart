import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/plans/models/date_plan.dart';
import 'package:couple_app/features/plans/models/date_plan_lists.dart';
import 'package:couple_app/features/plans/widgets/date_plan_hearts.dart';

/// A date plan in the planner list. Adapts to the plan's status: ideas show
/// the vibe and details, planned dates a countdown, past ones a "How did it
/// go?" prompt, done ones hearts and the reflection.
class DatePlanCard extends StatelessWidget {
  const DatePlanCard({
    super.key,
    required this.plan,
    required this.now,
    required this.currency,
    required this.onTap,
    this.onMarkDone,
    this.onPlan,
  });

  final DatePlan plan;
  final DateTime now;
  final String currency;
  final VoidCallback onTap;

  /// Shown as a button on past planned dates.
  final VoidCallback? onMarkDone;

  /// Shown as a button on ideas.
  final VoidCallback? onPlan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final at = plan.scheduledAt;
    final recap = plan.needsRecap(now);
    final cost = plan.estimatedCostMinor;

    final details = <(IconData, String)>[
      if (at != null && !plan.isIdea)
        (
          Icons.event_outlined,
          '${DateFormat.MMMEd().format(at)} · ${DateFormat.jm().format(at)}',
        ),
      if (plan.location.trim().isNotEmpty)
        (Icons.place_outlined, plan.location.trim()),
      if (cost != null)
        (
          Icons.account_balance_wallet_outlined,
          DatePlanCost.format(cost, currency),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: recap
            ? scheme.tertiaryContainer.withValues(alpha: .45)
            : scheme.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        plan.vibe.emoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.title.isEmpty ? 'Untitled date' : plan.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            plan.vibe.label,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (plan.isPlanned && at != null && !recap)
                      _Pill(
                        text: DatePlanLists.countdown(at, now),
                        background: scheme.primary,
                        foreground: scheme.onPrimary,
                      ),
                    if (plan.isDone && plan.rating != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: DatePlanHearts(rating: plan.rating, size: 16),
                      ),
                  ],
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final (icon, text) in details)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (plan.isDone && plan.reflection.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '“${plan.reflection.trim()}”',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ] else if (plan.isIdea && plan.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    plan.notes.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                if (recap && onMarkDone != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_outlined,
                        size: 18,
                        color: scheme.tertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'How did it go?',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.onTertiaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: onMarkDone,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 40),
                        ),
                        child: const Text('Mark done'),
                      ),
                    ],
                  ),
                ],
                if (plan.isIdea && onPlan != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: onPlan,
                      icon: const Icon(Icons.event_available_outlined),
                      label: const Text('Plan it'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
