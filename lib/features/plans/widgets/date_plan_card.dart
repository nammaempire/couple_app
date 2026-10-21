import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/plans/models/date_plan.dart';
import 'package:couple_app/features/plans/models/date_plan_lists.dart';
import 'package:couple_app/features/plans/widgets/date_plan_hearts.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';

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

    final b = theme.brightness;
    final preset = DatePlanLook.presetFor(plan.vibe);
    final fg = preset.foreground(b);
    final fgMuted = preset.foregroundMuted(b);
    final accent = preset.accent(b);
    final upcoming = plan.isPlanned && at != null && !recap;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: AnimatedGradientCard(
        preset: preset,
        onTap: onTap,
        radius: 24,
        // Only dates that are coming up drift; ideas and memories stay still.
        animate: upcoming,
        sheen: upcoming,
        glow: recap ? accent : null,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EmojiBadge(emoji: plan.vibe.emoji, preset: preset, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.title.isEmpty ? 'Untitled date' : plan.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        plan.vibe.label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: presetAccentText(preset, b),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (upcoming)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: GradientPill(
                      text: DatePlanLists.countdown(at, now),
                      preset: preset,
                      icon: Icons.hourglass_top_rounded,
                    ),
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
                      Icon(icon, size: 16, color: accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: fgMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (plan.isDone && plan.reflection.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(
                    alpha: preset.isDarkIn(b) ? .1 : .5,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '“${plan.reflection.trim()}”',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: fg,
                  ),
                ),
              ),
            ] else if (plan.isIdea && plan.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                plan.notes.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: fg),
              ),
            ],
            if (recap && onMarkDone != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.auto_awesome_outlined, size: 18, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'How did it go?',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: onMarkDone,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      shape: const StadiumBorder(),
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
                  style: TextButton.styleFrom(
                    foregroundColor: presetAccentText(preset, b),
                    backgroundColor: Colors.white.withValues(
                      alpha: preset.isDarkIn(b) ? .1 : .55,
                    ),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  icon: const Icon(Icons.event_available_outlined, size: 18),
                  label: const Text('Plan it'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The gradient each date vibe wears.
abstract final class DatePlanLook {
  static GradientPreset presetFor(DateVibe vibe) => switch (vibe) {
    DateVibe.cozy => GradientPreset.peach,
    DateVibe.adventure => GradientPreset.ocean,
    DateVibe.fancy => GradientPreset.gold,
    DateVibe.outdoors => GradientPreset.mint,
    DateVibe.food => GradientPreset.sunset,
    DateVibe.culture => GradientPreset.lavender,
    DateVibe.surprise => GradientPreset.festive,
  };
}
