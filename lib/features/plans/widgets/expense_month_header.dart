import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/plans/models/expense_math.dart';

/// "October 2026 · ₹12,450 spent" above each month of expenses.
class ExpenseMonthHeader extends StatelessWidget {
  const ExpenseMonthHeader({
    super.key,
    required this.month,
    required this.currency,
  });

  final ExpenseMonth month;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            DateFormat.yMMMM().format(DateTime(month.year, month.month)),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1.2,
              margin: const EdgeInsets.only(bottom: 6, right: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: .35),
                    theme.colorScheme.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          if (month.totalMinor > 0)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: ExpenseMath.format(month.totalMinor, currency),
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const TextSpan(text: ' spent'),
                ],
              ),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
        ],
      ),
    );
  }
}
