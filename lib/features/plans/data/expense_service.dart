import 'package:couple_app/core/backend/backend.dart';

import 'package:couple_app/features/plans/models/expense.dart';
import 'package:couple_app/features/plans/models/expense_math.dart';

/// Reads and writes `couples/{coupleId}/expenses`.
class ExpenseService {
  ExpenseService({Db? db}) : _db = db ?? Db.instance;

  final Db _db;

  CollectionReference<Map<String, dynamic>> _expenses(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('expenses');

  /// Every expense and settlement, newest first.
  Stream<List<Expense>> watchExpenses(String coupleId) {
    return _expenses(coupleId)
        .orderBy('spentOn', descending: true)
        .snapshots()
        .map((snap) => ExpenseMath.sorted(snap.docs.map(Expense.fromDoc)));
  }

  /// Adds [expense] when its id is empty, otherwise updates it.
  Future<void> save(String coupleId, Expense expense) async {
    final data = expense.toMap();
    if (expense.id.isEmpty) {
      await _expenses(coupleId).add({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _expenses(coupleId).doc(expense.id).set({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> delete(String coupleId, String expenseId) {
    return _expenses(coupleId).doc(expenseId).delete();
  }
}
