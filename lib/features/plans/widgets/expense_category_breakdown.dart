import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/plans/models/expense_math.dart';
import 'package:couple_app/features/plans/widgets/expense_tile.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';

/// "This month by category": a simple horizontal bar per category.
class ExpenseCategoryBreakdown extends StatelessWidget {
  const ExpenseCategoryBreakdown({
    super.key,
    required this.totals,
    required this.currency,
  });

  /// Largest first, as returned by [ExpenseMath.monthlyByCategory].
  final List<ExpenseCategoryTotal> totals;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final grand = totals.fold<int>(0, (sum, t) => sum + t.totalMinor);
    final largest = totals.isEmpty ? 0 : totals.first.totalMinor;

    return TintedCard(
      preset: GradientPreset.ocean,
      strength: .5,
      edge: true,
      radius: 24,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📊', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This month by category',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                ExpenseMath.format(grand, currency),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'What you spent together, not counting settlements.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          for (final t in totals) ...[
            _Bar(
              total: t,
              fraction: largest == 0 ? 0 : t.totalMinor / largest,
              percent: grand == 0 ? 0 : (t.totalMinor * 100 / grand).round(),
              currency: currency,
            ),
            if (t != totals.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.total,
    required this.fraction,
    required this.percent,
    required this.currency,
  });

  final ExpenseCategoryTotal total;
  final double fraction;
  final int percent;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final amount = ExpenseMath.format(total.totalMinor, currency);
    return Semantics(
      label: '${total.category.label}: $amount, $percent percent',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(total.category.emoji),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    total.category.label,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  '$percent%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  amount,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, constraints) {
                // Always show a sliver so tiny categories stay visible.
                final width = (constraints.maxWidth * fraction).clamp(
                  8.0,
                  constraints.maxWidth,
                );
                final preset = ExpenseLook.presetFor(total.category);
                final accent = preset.accent(theme.brightness);
                return Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.centerLeft,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    width: width,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: LinearGradient(
                        colors: [accent.withValues(alpha: .55), accent],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
