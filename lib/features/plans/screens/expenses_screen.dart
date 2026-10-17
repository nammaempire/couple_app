import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/empty_state.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/plans/models/expense.dart';
import 'package:couple_app/features/plans/models/expense_math.dart';
import 'package:couple_app/features/plans/providers/expense_providers.dart';
import 'package:couple_app/features/plans/screens/expense_editor_screen.dart';
import 'package:couple_app/features/plans/widgets/expense_balance_card.dart';
import 'package:couple_app/features/plans/widgets/expense_category_breakdown.dart';
import 'package:couple_app/features/plans/widgets/expense_currency_dialog.dart';
import 'package:couple_app/features/plans/widgets/expense_month_header.dart';
import 'package:couple_app/features/plans/widgets/expense_tile.dart';

/// Shared expenses: who owes whom, settling up, and where the money went.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  late final String _coupleId;
  late final String _myUid;

  bool _settling = false;

  @override
  void initState() {
    super.initState();
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
  }

  void _openEditor([Expense? expense]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ExpenseEditorScreen(expense: expense),
      ),
    );
  }

  Future<void> _pickCurrency(String current) async {
    final coupleService = ref.read(coupleServiceProvider);
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => ExpenseCurrencyDialog(current: current),
    );
    if (picked == null || picked == current) return;
    try {
      await coupleService.setCurrency(coupleId: _coupleId, currency: picked);
    } catch (_) {
      if (mounted) {
        context.showSnackMessage('Could not save. Check your connection.');
      }
    }
  }

  Future<void> _settleUp({
    required int balance,
    required String partnerUid,
    required String partnerName,
    required String currency,
  }) async {
    if (_settling || balance == 0) return;
    final service = ref.read(expenseServiceProvider);
    final amount = ExpenseMath.format(balance.abs(), currency);
    final who = balance > 0
        ? '$partnerName paid you $amount'
        : 'you paid $partnerName $amount';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.handshake_outlined),
        title: const Text('Settle up?'),
        content: Text(
          'This records that $who, so the balance goes back to zero for '
          'both of you.\n\nOnly do this once the money has actually changed '
          'hands.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Record payment'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final settlement = ExpenseMath.settlement(
      balance: balance,
      myUid: _myUid,
      partnerUid: partnerUid,
      on: DateTime.now(),
    );
    if (settlement == null) return;

    setState(() => _settling = true);
    try {
      await service.save(_coupleId, settlement);
      if (mounted) context.showSnackMessage('Settled up. You\'re all square.');
    } catch (_) {
      if (mounted) {
        context.showSnackMessage('Could not save. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _settling = false);
    }
  }

  Future<void> _confirmDeleteSettlement(
    Expense settlement,
    String partnerName,
    String currency,
  ) async {
    final service = ref.read(expenseServiceProvider);
    final amount = ExpenseMath.format(settlement.amountMinor, currency);
    final line = settlement.paidBy == _myUid
        ? 'You paid $partnerName $amount.'
        : '$partnerName paid you $amount.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this settlement?'),
        content: Text(
          '$line\n\nThis removes it for both of you, and the balance goes '
          'back to what it was before.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await service.delete(_coupleId, settlement.id);
    } catch (_) {
      if (mounted) {
        context.showSnackMessage('Could not delete. Check your connection.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final expenses = ref.watch(expensesProvider);
    final couple = ref.watch(coupleProvider).value;
    final partnerName = ref.watch(partnerNameProvider);
    final currency = couple?.currency ?? Couple.defaultCurrency;
    final partnerUid = couple?.partnerIdFor(_myUid);
    final all = expenses.value ?? const <Expense>[];
    final canAdd = partnerUid != null && expenses.hasValue;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared expenses'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              if (value == 'currency') _pickCurrency(currency);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'currency',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.currency_exchange),
                  title: const Text('Currency'),
                  trailing: Text(
                    currency,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              heroTag: 'expenses-add-fab',
              onPressed: _openEditor,
              icon: const Icon(Icons.add),
              label: const Text('Add expense'),
            )
          : null,
      body: _body(
        expenses: expenses,
        all: all,
        partnerUid: partnerUid,
        partnerName: partnerName,
        currency: currency,
        coupleLoaded: couple != null,
      ),
    );
  }

  Widget _body({
    required AsyncValue<List<Expense>> expenses,
    required List<Expense> all,
    required String? partnerUid,
    required String partnerName,
    required String currency,
    required bool coupleLoaded,
  }) {
    if ((!expenses.hasValue && !expenses.hasError) || !coupleLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (expenses.hasError && !expenses.hasValue) {
      return const EmptyState(
        icon: Icons.cloud_off,
        text: 'Could not load your expenses.',
      );
    }
    if (partnerUid == null) {
      return const EmptyState(
        icon: Icons.group_add_outlined,
        text: 'Shared expenses start once your partner joins.',
        padding: EdgeInsets.all(32),
      );
    }
    if (all.isEmpty) {
      return const EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        text:
            'No shared expenses yet.\nAdd one and we\'ll keep track of who '
            'owes whom.',
        padding: EdgeInsets.all(32),
      );
    }

    final balance = ExpenseMath.balance(all, _myUid, partnerUid);
    final months = ExpenseMath.byMonth(all);
    final now = DateTime.now();
    final thisMonth = ExpenseMath.monthlyByCategory(all, now.year, now.month);

    // Expenses behind the current balance: everything newer than the most
    // recent settlement (the list is newest first).
    var sinceSettled = 0;
    var settledBefore = false;
    for (final e in months.expand((m) => m.items)) {
      if (e.isSettlement) {
        settledBefore = true;
        break;
      }
      sinceSettled++;
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ExpenseBalanceCard(
            balance: balance,
            partnerName: partnerName,
            currency: currency,
            expenseCount: sinceSettled,
            settledBefore: settledBefore,
            settling: _settling,
            onSettleUp: () => _settleUp(
              balance: balance,
              partnerUid: partnerUid,
              partnerName: partnerName,
              currency: currency,
            ),
          ),
        ),
        if (thisMonth.isNotEmpty)
          SliverToBoxAdapter(
            child: ExpenseCategoryBreakdown(
              totals: thisMonth,
              currency: currency,
            ),
          ),
        for (final month in months) ...[
          SliverToBoxAdapter(
            child: ExpenseMonthHeader(month: month, currency: currency),
          ),
          SliverList.builder(
            itemCount: month.items.length,
            itemBuilder: (context, i) {
              final e = month.items[i];
              return ExpenseTile(
                expense: e,
                myUid: _myUid,
                partnerUid: partnerUid,
                partnerName: partnerName,
                currency: currency,
                // Settlements can't be edited; only whoever recorded one may
                // remove it.
                onTap: !e.isSettlement
                    ? () => _openEditor(e)
                    : e.createdBy == _myUid
                    ? () => _confirmDeleteSettlement(e, partnerName, currency)
                    : null,
              );
            },
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}
