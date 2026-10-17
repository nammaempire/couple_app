import 'package:flutter/material.dart';

import 'package:couple_app/features/plans/models/expense_math.dart';

/// Live "who carries what" for the expense being edited.
class ExpenseSplitPreview extends StatelessWidget {
  const ExpenseSplitPreview({
    super.key,
    required this.shares,
    required this.amountMinor,
    required this.payerUid,
    required this.myUid,
    required this.partnerUid,
    required this.partnerName,
    required this.currency,
  });

  /// Each person's share, or null while the amount or split is incomplete.
  final Map<String, int>? shares;
  final int? amountMinor;
  final String payerUid;
  final String myUid;
  final String partnerUid;
  final String partnerName;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = shares;
    final amount = amountMinor;

    final Widget body;
    if (s == null || amount == null) {
      body = Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              amount == null
                  ? 'Enter an amount to see each share.'
                  : 'Make the two shares add up to '
                        '${ExpenseMath.format(amount, currency)}.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    } else {
      final mine = s[myUid] ?? 0;
      final theirs = s[partnerUid] ?? 0;
      final paid = payerUid == myUid ? amount : 0;
      final effect = paid - mine;
      final summary = effect == 0
          ? 'No one owes anything for this.'
          : effect > 0
          ? '$partnerName will owe you ${ExpenseMath.format(effect, currency)}'
          : 'You\'ll owe $partnerName ${ExpenseMath.format(-effect, currency)}';

      Widget row(String label, int value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text(
              ExpenseMath.format(value, currency),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row('Your share', mine),
          row('$partnerName\'s share', theirs),
          Divider(height: 18, color: scheme.outlineVariant),
          Row(
            children: [
              Icon(
                effect == 0 ? Icons.check_circle_outline : Icons.swap_horiz,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  summary,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: body,
    );
  }
}
