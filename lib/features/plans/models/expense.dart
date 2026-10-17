import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// A shared cost, or a payment that settles up between the two of you.
enum ExpenseKind {
  expense('expense', 'Expense'),
  settlement('settlement', 'Settle up');

  const ExpenseKind(this.id, this.label);
  final String id;
  final String label;

  static ExpenseKind fromId(String? id) {
    for (final k in values) {
      if (k.id == id) return k;
    }
    return ExpenseKind.expense;
  }
}

/// Who carries how much of an expense.
enum ExpenseSplit {
  /// Half each. Odd paise go to the payer's share.
  equal('equal', 'Split equally', Icons.balance),

  /// The other person owes the whole amount.
  full('full', 'Owed in full', Icons.redeem_outlined),

  /// Exact amounts for each person, adding up to the total.
  custom('custom', 'Custom', Icons.tune);

  const ExpenseSplit(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;

  static ExpenseSplit fromId(String? id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return ExpenseSplit.equal;
  }
}

enum ExpenseCategory {
  food('food', 'Food', '🍽️', Icons.restaurant_outlined),
  groceries('groceries', 'Groceries', '🛒', Icons.shopping_basket_outlined),
  travel('travel', 'Travel', '✈️', Icons.flight_takeoff),
  home('home', 'Home', '🏠', Icons.home_outlined),
  bills('bills', 'Bills', '🧾', Icons.receipt_long_outlined),
  shopping('shopping', 'Shopping', '🛍️', Icons.shopping_bag_outlined),
  fun('fun', 'Fun', '🎉', Icons.celebration_outlined),
  gifts('gifts', 'Gifts', '🎁', Icons.card_giftcard_outlined),
  other('other', 'Other', '📌', Icons.more_horiz);

  const ExpenseCategory(this.id, this.label, this.emoji, this.icon);
  final String id;
  final String label;
  final String emoji;
  final IconData icon;

  static ExpenseCategory fromId(String? id) {
    for (final c in values) {
      if (c.id == id) return c;
    }
    return ExpenseCategory.other;
  }
}

/// One row in `couples/{coupleId}/expenses`. Amounts are integer minor
/// units (paise for INR), never doubles.
class Expense {
  final String id;
  final ExpenseKind kind;
  final String title;

  /// The total, in minor units. Always > 0 for valid expenses.
  final int amountMinor;

  /// The uid of whoever paid.
  final String paidBy;

  final ExpenseSplit split;

  /// Each person's share in minor units. Only used for [ExpenseSplit.custom].
  final Map<String, int>? shares;

  final ExpenseCategory category;

  /// The day it was spent (local midnight).
  final DateTime spentOn;

  final String note;
  final String createdBy;
  final DateTime? createdAt;

  static const maxTitleLength = 120;
  static const maxNoteLength = 500;

  /// ₹1 crore (or 10,000,000.00 of any currency).
  static const maxAmountMinor = 1000000000;

  static const settlementTitle = 'Settle up';

  const Expense({
    required this.id,
    required this.title,
    required this.amountMinor,
    required this.paidBy,
    required this.spentOn,
    required this.createdBy,
    this.kind = ExpenseKind.expense,
    this.split = ExpenseSplit.equal,
    this.shares,
    this.category = ExpenseCategory.other,
    this.note = '',
    this.createdAt,
  });

  bool get isSettlement => kind == ExpenseKind.settlement;

  factory Expense.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      fromMap(doc.id, doc.data() ?? const <String, dynamic>{});

  /// Builds an expense from stored fields. Missing or malformed fields fall
  /// back to safe defaults, so old or partial documents never crash.
  static Expense fromMap(String id, Map<String, dynamic> data) {
    final kind = ExpenseKind.fromId(_string(data['kind']));
    final settlement = kind == ExpenseKind.settlement;
    final split = settlement
        ? ExpenseSplit.full
        : ExpenseSplit.fromId(_string(data['split']));
    return Expense(
      id: id,
      kind: kind,
      title: _string(data['title']) ?? '',
      amountMinor: _int(data['amountMinor']) ?? 0,
      paidBy: _string(data['paidBy']) ?? '',
      split: split,
      shares: split == ExpenseSplit.custom ? _shares(data['shares']) : null,
      category: settlement
          ? ExpenseCategory.other
          : ExpenseCategory.fromId(_string(data['category'])),
      spentOn: _date(data['spentOn']) ?? _date(data['createdAt']) ?? _epoch,
      note: _string(data['note']) ?? '',
      createdBy: _string(data['createdBy']) ?? '',
      createdAt: _date(data['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    final settlement = isSettlement;
    final custom = !settlement && split == ExpenseSplit.custom;
    return {
      'kind': kind.id,
      'title': settlement ? settlementTitle : title.trim(),
      'amountMinor': amountMinor,
      'paidBy': paidBy,
      'split': settlement ? ExpenseSplit.full.id : split.id,
      'shares': custom ? Map<String, int>.of(shares ?? const {}) : null,
      'category': settlement ? ExpenseCategory.other.id : category.id,
      'spentOn': Timestamp.fromDate(
        DateTime(spentOn.year, spentOn.month, spentOn.day),
      ),
      'note': note.trim(),
      'createdBy': createdBy,
    };
  }

  Expense copyWith({
    String? title,
    int? amountMinor,
    String? paidBy,
    ExpenseSplit? split,
    Map<String, int>? shares,
    bool clearShares = false,
    ExpenseCategory? category,
    DateTime? spentOn,
    String? note,
  }) {
    return Expense(
      id: id,
      kind: kind,
      title: title ?? this.title,
      amountMinor: amountMinor ?? this.amountMinor,
      paidBy: paidBy ?? this.paidBy,
      split: split ?? this.split,
      shares: clearShares ? null : (shares ?? this.shares),
      category: category ?? this.category,
      spentOn: spentOn ?? this.spentOn,
      note: note ?? this.note,
      createdBy: createdBy,
      createdAt: createdAt,
    );
  }

  static final _epoch = DateTime(2000);

  static String? _string(Object? v) => v is String ? v : null;

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num && v.isFinite) return v.round();
    return null;
  }

  static DateTime? _date(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static Map<String, int>? _shares(Object? raw) {
    if (raw is! Map) return null;
    final result = <String, int>{};
    raw.forEach((key, value) {
      final amount = _int(value);
      if (key is String && amount != null) result[key] = amount;
    });
    return result.isEmpty ? null : result;
  }
}
