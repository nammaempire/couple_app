import 'package:flutter/material.dart';

import 'package:couple_app/features/plans/models/expense_math.dart';

/// Picks the currency for shared expenses. Pops with the chosen ISO code.
class ExpenseCurrencyDialog extends StatelessWidget {
  const ExpenseCurrencyDialog({super.key, required this.current});

  final String current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SimpleDialog(
      title: const Text('Currency'),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            'Changes how amounts are shown for both of you. '
            'Amounts are not converted.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final code in ExpenseMath.currencies)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: SizedBox(
              width: 40,
              child: Text(
                ExpenseMath.symbolFor(code),
                style: theme.textTheme.titleMedium,
              ),
            ),
            title: Text(ExpenseMath.currencyNames[code] ?? code),
            subtitle: Text(code),
            trailing: code == current
                ? Icon(Icons.check, color: theme.colorScheme.primary)
                : null,
            selected: code == current,
            onTap: () => Navigator.pop(context, code),
          ),
      ],
    );
  }
}
