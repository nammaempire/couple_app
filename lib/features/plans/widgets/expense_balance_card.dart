import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
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
    final square = balance == 0;
    final owedToMe = balance > 0;

    final b = theme.brightness;
    final preset = square
        ? GradientPreset.lavender
        : owedToMe
        ? GradientPreset.mint
        : GradientPreset.peach;
    final foreground = preset.foreground(b);
    final muted = preset.foregroundMuted(b);
    final buttonBg = preset.isDarkIn(b)
        ? preset.accentDark
        : Color.lerp(preset.accentLight, Colors.black, .35)!;
    final buttonFg = preset.isDarkIn(b)
        ? const Color(0xFF2A1020)
        : Colors.white;

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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: AnimatedGradientCard(
          preset: preset,
          radius: 26,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(
                          alpha: preset.isDarkIn(b) ? .14 : .65,
                        ),
                      ),
                      child: Icon(
                        square
                            ? Icons.check_circle_outline
                            : Icons.account_balance_wallet_outlined,
                        size: 17,
                        color: preset.accent(b),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Balance',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w700,
                      ),
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
                      backgroundColor: buttonBg,
                      foregroundColor: buttonFg,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: const StadiumBorder(),
                    ),
                    icon: settling
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: buttonFg,
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
      ),
    );
  }
}
