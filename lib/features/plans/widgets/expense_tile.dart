import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/plans/models/expense.dart';
import 'package:couple_app/features/plans/models/expense_math.dart';

/// One expense or settlement in the list, with what it means for you.
class ExpenseTile extends StatelessWidget {
  const ExpenseTile({
    super.key,
    required this.expense,
    required this.myUid,
    required this.partnerUid,
    required this.partnerName,
    required this.currency,
    this.onTap,
  });

  final Expense expense;
  final String myUid;
  final String partnerUid;
  final String partnerName;
  final String currency;

  /// Null when the entry cannot be opened (a settlement someone else recorded).
  final VoidCallback? onTap;

  String get _payerName {
    if (expense.paidBy == myUid) return 'You';
    if (expense.paidBy == partnerUid) return partnerName;
    return 'Someone';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final amount = ExpenseMath.format(expense.amountMinor, currency);
    final day = DateFormat.MMMd().format(expense.spentOn);

    if (expense.isSettlement) {
      final iPaid = expense.paidBy == myUid;
      final line = iPaid ? 'You paid $partnerName' : '$partnerName paid you';
      return ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: CircleAvatar(
          backgroundColor: scheme.secondaryContainer,
          foregroundColor: scheme.onSecondaryContainer,
          child: const Icon(Icons.handshake_outlined, size: 20),
        ),
        title: Text(line),
        subtitle: Text('Settled up · $day'),
        trailing: Text(
          amount,
          style: theme.textTheme.titleSmall?.copyWith(
            color: muted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
    }

    final effect = ExpenseMath.effectFor(expense, myUid, partnerUid);
    final String effectText;
    final Color effectColor;
    if (effect > 0) {
      effectText = '$partnerName owes ${ExpenseMath.format(effect, currency)}';
      effectColor = scheme.primary;
    } else if (effect < 0) {
      effectText = 'You owe ${ExpenseMath.format(-effect, currency)}';
      effectColor = scheme.tertiary;
    } else {
      effectText = 'Nothing owed';
      effectColor = muted;
    }

    final splitText = switch (expense.split) {
      ExpenseSplit.equal => 'split equally',
      ExpenseSplit.full =>
        expense.paidBy == myUid ? 'for $partnerName' : 'for you',
      ExpenseSplit.custom => 'custom split',
    };

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: CircleAvatar(
        backgroundColor: scheme.surfaceContainerHighest,
        child: Text(
          expense.category.emoji,
          style: const TextStyle(fontSize: 18),
        ),
      ),
      title: Text(
        expense.title.isEmpty ? expense.category.label : expense.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$_payerName paid · $splitText · $day',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            amount,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              effectText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: effectColor),
            ),
          ),
        ],
      ),
    );
  }
}
