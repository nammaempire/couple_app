import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/plans/models/expense.dart';
import 'package:couple_app/features/plans/models/expense_math.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';

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
      return _row(
        context,
        muted: true,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.secondaryContainer,
          ),
          child: Icon(
            Icons.handshake_outlined,
            size: 20,
            color: scheme.onSecondaryContainer,
          ),
        ),
        title: line,
        subtitle: 'Settled up · $day',
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

    final preset = ExpenseLook.presetFor(expense.category);
    return _row(
      context,
      preset: preset,
      leading: EmojiBadge(
        emoji: expense.category.emoji,
        preset: preset,
        size: 44,
      ),
      title: expense.title.isEmpty ? expense.category.label : expense.title,
      subtitle: '$_payerName paid · $splitText · $day',
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
              style: theme.textTheme.labelSmall?.copyWith(
                color: effectColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required Widget leading,
    required String title,
    required String subtitle,
    required Widget trailing,
    GradientPreset preset = GradientPreset.blush,
    bool muted = false,
  }) {
    final theme = Theme.of(context);
    return TintedCard(
      preset: preset,
      muted: muted,
      strength: .5,
      onTap: onTap,
      radius: 20,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

/// The gradient each expense category wears.
abstract final class ExpenseLook {
  static GradientPreset presetFor(ExpenseCategory c) => switch (c) {
    ExpenseCategory.food => GradientPreset.sunset,
    ExpenseCategory.groceries => GradientPreset.mint,
    ExpenseCategory.travel => GradientPreset.ocean,
    ExpenseCategory.home => GradientPreset.peach,
    ExpenseCategory.bills => GradientPreset.sunny,
    ExpenseCategory.shopping => GradientPreset.blush,
    ExpenseCategory.fun => GradientPreset.festive,
    ExpenseCategory.gifts => GradientPreset.lavender,
    ExpenseCategory.other => GradientPreset.gold,
  };
}
