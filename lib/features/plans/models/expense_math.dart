import 'package:intl/intl.dart';

import 'package:couple_app/features/plans/models/expense.dart';

/// A month of expenses, newest first, with the total spent that month.
class ExpenseMonth {
  final int year;
  final int month;
  final List<Expense> items;

  /// Money spent together that month. Settlements are not spending.
  final int totalMinor;

  const ExpenseMonth({
    required this.year,
    required this.month,
    required this.items,
    required this.totalMinor,
  });
}

/// One category's spending in a period.
class ExpenseCategoryTotal {
  final ExpenseCategory category;
  final int totalMinor;

  const ExpenseCategoryTotal(this.category, this.totalMinor);
}

/// Pure money logic for shared expenses. Everything is integer minor units
/// (paise), so shares always add up exactly and nothing drifts.
class ExpenseMath {
  const ExpenseMath._();

  /// Currencies offered in the picker.
  static const currencies = [
    'INR',
    'USD',
    'EUR',
    'GBP',
    'AED',
    'SGD',
    'AUD',
    'CAD',
  ];

  static const currencyNames = {
    'INR': 'Indian rupee',
    'USD': 'US dollar',
    'EUR': 'Euro',
    'GBP': 'British pound',
    'AED': 'UAE dirham',
    'SGD': 'Singapore dollar',
    'AUD': 'Australian dollar',
    'CAD': 'Canadian dollar',
  };

  // ---------------------------------------------------------------- shares

  /// How much of [expense] each member carries, keyed by uid. The values
  /// always sum to `expense.amountMinor`.
  ///
  /// - equal: half each; an odd paisa goes to the payer.
  /// - full (and settlements): the other member carries it all.
  /// - custom: the stored shares, if they cover the members and add up
  ///   exactly; otherwise (a damaged document) it falls back to equal.
  ///
  /// [memberIds] are the two members. Returns an empty map if the payer is
  /// not one of them or the amount is not positive.
  static Map<String, int> sharesFor(Expense expense, List<String> memberIds) {
    final amount = expense.amountMinor;
    final payer = expense.paidBy;
    if (amount <= 0 || memberIds.length != 2 || !memberIds.contains(payer)) {
      return const {};
    }
    final other = memberIds.firstWhere((id) => id != payer);
    if (other == payer) return const {};

    final split = expense.isSettlement ? ExpenseSplit.full : expense.split;
    switch (split) {
      case ExpenseSplit.full:
        return {payer: 0, other: amount};
      case ExpenseSplit.custom:
        final custom = validCustomShares(
          expense.shares,
          amount: amount,
          memberIds: memberIds,
        );
        if (custom != null) return custom;
        return equalShares(amount, payer: payer, other: other);
      case ExpenseSplit.equal:
        return equalShares(amount, payer: payer, other: other);
    }
  }

  /// Half each, with the odd paisa on the payer's side.
  static Map<String, int> equalShares(
    int amount, {
    required String payer,
    required String other,
  }) {
    final otherShare = amount ~/ 2;
    return {payer: amount - otherShare, other: otherShare};
  }

  /// [shares] limited to the two members, or null unless both are present,
  /// none is negative and they add up to exactly [amount].
  static Map<String, int>? validCustomShares(
    Map<String, int>? shares, {
    required int amount,
    required List<String> memberIds,
  }) {
    if (shares == null) return null;
    final result = <String, int>{};
    var sum = 0;
    for (final id in memberIds) {
      final share = shares[id];
      if (share == null || share < 0) return null;
      result[id] = share;
      sum += share;
    }
    return sum == amount ? result : null;
  }

  /// What [expense] alone does to the balance, from [myUid]'s side:
  /// positive means the partner owes me that much more.
  static int effectFor(Expense expense, String myUid, String partnerUid) {
    final shares = sharesFor(expense, [myUid, partnerUid]);
    if (shares.isEmpty) return 0;
    final paid = expense.paidBy == myUid ? expense.amountMinor : 0;
    return paid - shares[myUid]!;
  }

  /// The running balance between the two of you. Positive: the partner owes
  /// me. Negative: I owe the partner. Rows paid by anyone else are ignored.
  static int balance(
    Iterable<Expense> expenses,
    String myUid,
    String partnerUid,
  ) {
    var total = 0;
    for (final e in expenses) {
      total += effectFor(e, myUid, partnerUid);
    }
    return total;
  }

  /// The payment that brings [balance] to zero, or null when already square.
  /// The debtor pays the whole amount for the other person (split full).
  static Expense? settlement({
    required int balance,
    required String myUid,
    required String partnerUid,
    required DateTime on,
  }) {
    if (balance == 0) return null;
    return Expense(
      id: '',
      kind: ExpenseKind.settlement,
      title: Expense.settlementTitle,
      amountMinor: balance.abs(),
      paidBy: balance > 0 ? partnerUid : myUid,
      split: ExpenseSplit.full,
      category: ExpenseCategory.other,
      spentOn: DateTime(on.year, on.month, on.day),
      createdBy: myUid,
    );
  }

  // --------------------------------------------------------------- totals

  /// Newest first: by day spent, then by when it was added. Rows still
  /// waiting for a server time count as newest.
  static List<Expense> sorted(Iterable<Expense> expenses) {
    return expenses.toList()..sort((a, b) {
      final byDay = b.spentOn.compareTo(a.spentOn);
      if (byDay != 0) return byDay;
      final ca = a.createdAt;
      final cb = b.createdAt;
      if (ca == null && cb == null) return 0;
      if (ca == null) return -1;
      if (cb == null) return 1;
      return cb.compareTo(ca);
    });
  }

  /// Expenses grouped by calendar month, newest month first.
  static List<ExpenseMonth> byMonth(Iterable<Expense> expenses) {
    final months = <ExpenseMonth>[];
    List<Expense>? current;
    int? year;
    int? month;

    void flush() {
      final items = current;
      if (items == null) return;
      months.add(
        ExpenseMonth(
          year: year!,
          month: month!,
          items: items,
          totalMinor: totalSpent(items),
        ),
      );
    }

    for (final e in sorted(expenses)) {
      if (e.spentOn.year != year || e.spentOn.month != month) {
        flush();
        year = e.spentOn.year;
        month = e.spentOn.month;
        current = [];
      }
      current!.add(e);
    }
    flush();
    return months;
  }

  /// Sum of real spending in [expenses], leaving out settlements.
  static int totalSpent(Iterable<Expense> expenses) {
    var total = 0;
    for (final e in expenses) {
      if (!e.isSettlement && e.amountMinor > 0) total += e.amountMinor;
    }
    return total;
  }

  /// Spending per category in the given month, largest first. Settlements
  /// and empty categories are left out.
  static List<ExpenseCategoryTotal> monthlyByCategory(
    Iterable<Expense> expenses,
    int year,
    int month,
  ) {
    final totals = <ExpenseCategory, int>{};
    for (final e in expenses) {
      if (e.isSettlement || e.amountMinor <= 0) continue;
      if (e.spentOn.year != year || e.spentOn.month != month) continue;
      totals[e.category] = (totals[e.category] ?? 0) + e.amountMinor;
    }
    final list = [
      for (final entry in totals.entries)
        ExpenseCategoryTotal(entry.key, entry.value),
    ];
    list.sort((a, b) {
      final byTotal = b.totalMinor.compareTo(a.totalMinor);
      return byTotal != 0 ? byTotal : a.category.index - b.category.index;
    });
    return list;
  }

  /// The balance in plain words: "Ravi owes you ₹1,250", "You owe Ravi
  /// ₹300" or "You're all square".
  static String balanceText(int balance, String partnerName, String currency) {
    if (balance == 0) return 'You\'re all square';
    final amount = format(balance.abs(), currency);
    return balance > 0
        ? '$partnerName owes you $amount'
        : 'You owe $partnerName $amount';
  }

  // ---------------------------------------------------------------- input

  /// Parses typed money like `1,250.50` into minor units (`125050`).
  ///
  /// Accepts digits with optional commas/spaces and up to two decimals.
  /// Returns null for anything else, including zero, negatives and amounts
  /// over [Expense.maxAmountMinor].
  static int? parseAmount(String input) {
    final minor = parseMinor(input);
    if (minor == null || minor <= 0 || minor > Expense.maxAmountMinor) {
      return null;
    }
    return minor;
  }

  /// Like [parseAmount] but allows zero (for a custom share someone does
  /// not pay into). Returns null when malformed or too large.
  static int? parseShare(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 0;
    final minor = parseMinor(trimmed);
    if (minor == null || minor > Expense.maxAmountMinor) return null;
    return minor;
  }

  /// The raw conversion with no range check: null if not a plain amount.
  static int? parseMinor(String input) {
    final cleaned = input.replaceAll(RegExp(r'[,\s]'), '');
    final match = RegExp(r'^(\d*)(?:\.(\d{0,2}))?$').firstMatch(cleaned);
    if (match == null) return null;
    final whole = match.group(1)!;
    final fraction = match.group(2) ?? '';
    if (whole.isEmpty && fraction.isEmpty) return null;
    // Anything this long is far beyond the limit; avoid int overflow.
    if (whole.length > 12) return null;
    final units = whole.isEmpty ? 0 : int.parse(whole);
    final cents = int.parse(fraction.padRight(2, '0'));
    return units * 100 + cents;
  }

  /// Why [input] is not a valid amount, or null when it is.
  static String? amountError(String input, String currency) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'Enter an amount';
    if (trimmed.startsWith('-')) return 'Enter an amount above zero';
    final minor = parseMinor(trimmed);
    if (minor == null) {
      return trimmed.contains('.') &&
              RegExp(r'\.\d{3,}').hasMatch(trimmed.replaceAll(',', ''))
          ? 'Use at most 2 decimal places'
          : 'Enter an amount like 1,250.50';
    }
    if (minor <= 0) return 'Enter an amount above zero';
    if (minor > Expense.maxAmountMinor) {
      return 'Keep it under ${format(Expense.maxAmountMinor, currency)}';
    }
    return null;
  }

  /// Minor units as editable text: `125050` → `1250.50`, `125000` → `1250`.
  static String toInput(int minor) {
    final units = minor ~/ 100;
    final cents = minor % 100;
    return cents == 0 ? '$units' : '$units.${cents.toString().padLeft(2, '0')}';
  }

  // ----------------------------------------------------------- formatting

  /// Symbols that would otherwise be ambiguous (`$`) or unfamiliar (`dh`).
  static const _clearSymbols = {
    'AED': 'AED ',
    'SGD': r'S$',
    'AUD': r'A$',
    'CAD': r'C$',
  };

  static NumberFormat _formatter(String currency, {required bool whole}) {
    // Lakh/crore grouping for rupees.
    final locale = currency == 'INR' ? 'en_IN' : 'en_US';
    final digits = whole ? 0 : 2;
    final symbol = _clearSymbols[currency];
    if (symbol != null) {
      return NumberFormat.currency(
        locale: locale,
        name: currency,
        symbol: symbol,
        decimalDigits: digits,
      );
    }
    return NumberFormat.simpleCurrency(
      locale: locale,
      name: currency,
      decimalDigits: digits,
    );
  }

  /// `125050` in INR → `₹1,250.50`; whole amounts drop the decimals
  /// (`₹1,250`). Negative values keep their sign.
  static String format(int minor, String currency) {
    final whole = minor % 100 == 0;
    return _formatter(currency, whole: whole).format(minor / 100);
  }

  /// The symbol shown before the amount field, e.g. `₹` or `$`.
  static String symbolFor(String currency) =>
      _formatter(currency, whole: true).currencySymbol.trim();
}
