import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/plans/data/expense_service.dart';
import 'package:couple_app/features/plans/models/expense.dart';

final expenseServiceProvider = Provider<ExpenseService>(
  (ref) => ExpenseService(),
);

/// Shared expenses and settlements, newest first.
final expensesProvider = StreamProvider.autoDispose<List<Expense>>(
  (ref) => ref
      .watch(expenseServiceProvider)
      .watchExpenses(ref.watch(currentCoupleIdProvider)),
);
