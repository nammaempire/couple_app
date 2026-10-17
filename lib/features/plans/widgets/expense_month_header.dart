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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              DateFormat.yMMMM().format(DateTime(month.year, month.month)),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
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
