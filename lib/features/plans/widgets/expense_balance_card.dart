import 'package:flutter/material.dart';

import 'package:couple_app/features/plans/models/expense_math.dart';

/// The headline: who owes whom, in plain words, with a Settle up button.
class ExpenseBalanceCard extends StatelessWidget {
  const ExpenseBalanceCard({
    super.key,
    required this.balance,
    required this.partnerName,
    required this.currency,
    required this.expenseCount,
    required this.onSettleUp,
    this.settledBefore = false,
    this.settling = false,
  });

  /// Positive: the partner owes you. Negative: you owe the partner.
  final int balance;
  final String partnerName;
  final String currency;

  /// Expenses behind the current balance (since the last settlement).
  final int expenseCount;

  /// Whether you have settled up before, for the caption.
  final bool settledBefore;
  final VoidCallback onSettleUp;
  final bool settling;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final square = balance == 0;
    final owedToMe = balance > 0;

    final background = square
        ? scheme.surfaceContainerHigh
        : owedToMe
        ? scheme.primaryContainer
        : scheme.tertiaryContainer;
    final foreground = square
        ? scheme.onSurface
        : owedToMe
        ? scheme.onPrimaryContainer
        : scheme.onTertiaryContainer;
    final muted = foreground.withValues(alpha: 0.72);

    final lead = square
        ? 'You\'re all square'
        : owedToMe
        ? '$partnerName owes you'
        : 'You owe $partnerName';
    final caption = square
        ? (expenseCount == 0
              ? 'Add what you spend together and we\'ll keep the maths.'
              : 'Nothing to settle right now.')
        : 'From ${expenseCount == 1 ? '1 shared expense' : '$expenseCount shared expenses'}'
              '${settledBefore ? ' since you last settled up' : ''}.';

    return Semantics(
      container: true,
      label: ExpenseMath.balanceText(balance, partnerName, currency),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(24),
        ),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    square
                        ? Icons.check_circle_outline
                        : Icons.account_balance_wallet_outlined,
                    size: 18,
                    color: muted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Balance',
                    style: theme.textTheme.labelLarge?.copyWith(color: muted),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                lead,
                style:
                    (square
                            ? theme.textTheme.headlineSmall
                            : theme.textTheme.titleMedium)
                        ?.copyWith(
                          color: foreground,
                          fontWeight: square ? FontWeight.w700 : null,
                        ),
              ),
              if (!square) ...[
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    ExpenseMath.format(balance.abs(), currency),
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                caption,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              if (!square) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: settling ? null : onSettleUp,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    backgroundColor: foreground,
                    foregroundColor: background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: settling
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: background,
                          ),
                        )
                      : const Icon(Icons.handshake_outlined, size: 20),
                  label: const Text('Settle up'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
