import 'package:couple_app/core/backend/backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/core/theme/app_theme.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/plans/data/expense_service.dart';
import 'package:couple_app/features/plans/models/expense.dart';
import 'package:couple_app/features/plans/models/expense_math.dart';
import 'package:couple_app/features/plans/providers/expense_providers.dart';
import 'package:couple_app/features/plans/screens/expense_editor_screen.dart';
import 'package:couple_app/features/plans/screens/expenses_screen.dart';

const me = 'me';
const partner = 'partner';
const members = [me, partner];

Expense expense({
  String id = 'x1',
  int amount = 1000,
  String paidBy = me,
  ExpenseSplit split = ExpenseSplit.equal,
  Map<String, int>? shares,
  ExpenseCategory category = ExpenseCategory.food,
  DateTime? spentOn,
  DateTime? createdAt,
  ExpenseKind kind = ExpenseKind.expense,
}) => Expense(
  id: id,
  kind: kind,
  title: 'Dinner',
  amountMinor: amount,
  paidBy: paidBy,
  split: split,
  shares: shares,
  category: category,
  spentOn: spentOn ?? DateTime(2026, 10, 12),
  createdBy: me,
  createdAt: createdAt,
);

/// Records saves instead of talking to the database.
class FakeExpenseService implements ExpenseService {
  final saved = <Expense>[];
  final deleted = <String>[];

  @override
  Stream<List<Expense>> watchExpenses(String coupleId) => const Stream.empty();

  @override
  Future<void> save(String coupleId, Expense expense) async =>
      saved.add(expense);

  @override
  Future<void> delete(String coupleId, String expenseId) async =>
      deleted.add(expenseId);
}

Future<FakeExpenseService> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  List<Expense> expenses = const [],
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final service = FakeExpenseService();
  const couple = Couple(
    id: 'c1',
    inviteCode: 'ABC234',
    memberIds: [me, partner],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithBuild(
          (ref, notifier) =>
              const AppUser(uid: me, displayName: 'Asha', coupleId: 'c1'),
        ),
        coupleProvider.overrideWith((ref) => Stream.value(couple)),
        partnerNameProvider.overrideWithValue('Ravi'),
        expenseServiceProvider.overrideWithValue(service),
        expensesProvider.overrideWith((ref) => Stream.value(expenses)),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: screen),
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

int sumOf(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);

void main() {
  group('enums', () {
    test('fromId falls back safely', () {
      expect(ExpenseKind.fromId(null), ExpenseKind.expense);
      expect(ExpenseKind.fromId('settlement'), ExpenseKind.settlement);
      expect(ExpenseSplit.fromId('nope'), ExpenseSplit.equal);
      expect(ExpenseSplit.fromId('custom'), ExpenseSplit.custom);
      expect(ExpenseCategory.fromId(''), ExpenseCategory.other);
      expect(ExpenseCategory.fromId('groceries'), ExpenseCategory.groceries);
    });

    test('ids are unique and stable', () {
      expect(ExpenseCategory.values.map((c) => c.id).toSet().length, 9);
      expect(ExpenseSplit.values.map((s) => s.id), ['equal', 'full', 'custom']);
    });
  });

  group('Expense map round-trip', () {
    test('custom expense survives toMap → fromMap', () {
      final original = expense(
        amount: 125050,
        split: ExpenseSplit.custom,
        shares: {me: 25050, partner: 100000},
        category: ExpenseCategory.travel,
        spentOn: DateTime(2026, 3, 9, 18, 45),
      ).copyWith(note: '  train  ', title: '  Goa tickets ');
      final map = original.toMap();
      expect(map['kind'], 'expense');
      expect(map['title'], 'Goa tickets');
      expect(map['note'], 'train');
      expect(map['amountMinor'], 125050);
      expect(map['split'], 'custom');
      expect(map['shares'], {me: 25050, partner: 100000});
      expect(map['category'], 'travel');
      // Date-only: stored as local midnight.
      expect((map['spentOn'] as Timestamp).toDate(), DateTime(2026, 3, 9));
      expect(map.containsKey('createdAt'), isFalse);

      final back = Expense.fromMap('x1', map);
      expect(back.amountMinor, 125050);
      expect(back.split, ExpenseSplit.custom);
      expect(back.shares, {me: 25050, partner: 100000});
      expect(back.category, ExpenseCategory.travel);
      expect(back.spentOn, DateTime(2026, 3, 9));
      expect(back.paidBy, me);
      expect(back.createdBy, me);
    });

    test('shares are only stored for custom splits', () {
      final map = expense(shares: {me: 1, partner: 999}).toMap();
      expect(map['shares'], isNull);
    });

    test('settlements are normalised to full / other', () {
      final map = expense(
        kind: ExpenseKind.settlement,
        split: ExpenseSplit.equal,
        category: ExpenseCategory.food,
      ).toMap();
      expect(map['kind'], 'settlement');
      expect(map['title'], 'Settle up');
      expect(map['split'], 'full');
      expect(map['category'], 'other');

      final back = Expense.fromMap('s', {...map, 'split': 'equal'});
      expect(back.split, ExpenseSplit.full);
    });

    test('partial and malformed documents do not crash', () {
      final e = Expense.fromMap('old', {
        'amountMinor': 1250.0,
        'split': 'custom',
        'shares': {me: 'lots', partner: 1250, 3: 4},
        'category': 42,
      });
      expect(e.title, '');
      expect(e.amountMinor, 1250);
      expect(e.kind, ExpenseKind.expense);
      expect(e.shares, {partner: 1250});
      expect(e.category, ExpenseCategory.other);
      expect(e.paidBy, '');

      final empty = Expense.fromMap('empty', const {});
      expect(empty.amountMinor, 0);
      expect(empty.split, ExpenseSplit.equal);
      expect(empty.shares, isNull);
      // Unknown payer: contributes nothing to the balance.
      expect(ExpenseMath.balance([empty], me, partner), 0);
    });
  });

  group('sharesFor', () {
    test('equal split of an even amount is half each', () {
      expect(ExpenseMath.sharesFor(expense(amount: 1000), members), {
        me: 500,
        partner: 500,
      });
    });

    test('odd paise go to the payer and shares sum exactly', () {
      final mine = ExpenseMath.sharesFor(expense(amount: 1001), members);
      expect(mine, {me: 501, partner: 500});
      final theirs = ExpenseMath.sharesFor(
        expense(amount: 1001, paidBy: partner),
        members,
      );
      expect(theirs, {partner: 501, me: 500});
      for (final amount in [1, 3, 99, 12345, 999999999]) {
        final s = ExpenseMath.sharesFor(expense(amount: amount), members);
        expect(sumOf(s), amount, reason: 'amount $amount');
        expect(s[me]! - s[partner]!, inInclusiveRange(0, 1));
      }
    });

    test('one paisa: the payer carries it', () {
      expect(ExpenseMath.sharesFor(expense(amount: 1), members), {
        me: 1,
        partner: 0,
      });
    });

    test('full split puts the whole amount on the other person', () {
      expect(
        ExpenseMath.sharesFor(
          expense(amount: 4999, split: ExpenseSplit.full),
          members,
        ),
        {me: 0, partner: 4999},
      );
    });

    test('custom split uses the stored shares', () {
      final e = expense(
        amount: 125050,
        paidBy: partner,
        split: ExpenseSplit.custom,
        shares: {me: 100000, partner: 25050},
      );
      expect(ExpenseMath.sharesFor(e, members), {me: 100000, partner: 25050});
    });

    test('custom split with a zero share is allowed', () {
      final e = expense(
        amount: 800,
        split: ExpenseSplit.custom,
        shares: {me: 800, partner: 0},
      );
      expect(ExpenseMath.sharesFor(e, members), {me: 800, partner: 0});
      expect(ExpenseMath.effectFor(e, me, partner), 0);
    });

    test('broken custom shares fall back to an equal split', () {
      for (final bad in <Map<String, int>?>[
        null,
        {me: 100},
        {me: 600, partner: 500},
        {me: -100, partner: 1100},
        {me: 500, 'stranger': 500},
      ]) {
        final e = expense(split: ExpenseSplit.custom, shares: bad);
        expect(ExpenseMath.sharesFor(e, members), {
          me: 500,
          partner: 500,
        }, reason: '$bad');
      }
    });

    test('validCustomShares drops extra keys and checks the sum', () {
      expect(
        ExpenseMath.validCustomShares(
          {me: 300, partner: 700, 'x': 5},
          amount: 1000,
          memberIds: members,
        ),
        {me: 300, partner: 700},
      );
      expect(
        ExpenseMath.validCustomShares(
          {me: 300, partner: 699},
          amount: 1000,
          memberIds: members,
        ),
        isNull,
      );
    });

    test('unknown payer or bad amount gives no shares', () {
      expect(ExpenseMath.sharesFor(expense(paidBy: 'ghost'), members), isEmpty);
      expect(ExpenseMath.sharesFor(expense(amount: 0), members), isEmpty);
      expect(ExpenseMath.sharesFor(expense(), [me]), isEmpty);
    });
  });

  group('balance', () {
    test('positive when the partner owes me, negative when I owe', () {
      expect(ExpenseMath.balance([expense(amount: 1000)], me, partner), 500);
      expect(ExpenseMath.balance([expense(amount: 1000)], partner, me), -500);
    });

    test('combines equal, full and custom splits', () {
      final list = [
        expense(amount: 1001), // partner owes 500
        expense(amount: 3000, split: ExpenseSplit.full), // partner owes 3000
        expense(
          amount: 2000,
          paidBy: partner,
          split: ExpenseSplit.custom,
          shares: {me: 1500, partner: 500},
        ), // I owe 1500
        expense(amount: 600, paidBy: partner), // I owe 300
      ];
      expect(ExpenseMath.balance(list, me, partner), 500 + 3000 - 1500 - 300);
      // Same data seen from the other side is the exact opposite.
      expect(
        ExpenseMath.balance(list, partner, me),
        -ExpenseMath.balance(list, me, partner),
      );
    });

    test('empty list is all square', () {
      expect(ExpenseMath.balance(const [], me, partner), 0);
    });

    test('is described in plain words', () {
      expect(
        ExpenseMath.balanceText(125000, 'Ravi', 'INR'),
        'Ravi owes you ₹1,250',
      );
      expect(
        ExpenseMath.balanceText(-30000, 'Ravi', 'INR'),
        'You owe Ravi ₹300',
      );
      expect(ExpenseMath.balanceText(0, 'Ravi', 'INR'), 'You\'re all square');
      expect(
        ExpenseMath.balanceText(-1999, 'Sam', 'USD'),
        r'You owe Sam $19.99',
      );
    });

    test('effectFor matches each row of the balance', () {
      expect(ExpenseMath.effectFor(expense(amount: 1001), me, partner), 500);
      expect(
        ExpenseMath.effectFor(
          expense(amount: 1001, paidBy: partner),
          me,
          partner,
        ),
        -500,
      );
    });
  });

  group('settlement', () {
    test('when the partner owes me, the partner pays', () {
      final list = [expense(amount: 2501)];
      final balance = ExpenseMath.balance(list, me, partner);
      expect(balance, 1250);
      final s = ExpenseMath.settlement(
        balance: balance,
        myUid: me,
        partnerUid: partner,
        on: DateTime(2026, 10, 15, 21, 30),
      )!;
      expect(s.kind, ExpenseKind.settlement);
      expect(s.paidBy, partner);
      expect(s.split, ExpenseSplit.full);
      expect(s.amountMinor, 1250);
      expect(s.category, ExpenseCategory.other);
      expect(s.title, 'Settle up');
      expect(s.id, isEmpty);
      expect(s.createdBy, me);
      expect(s.spentOn, DateTime(2026, 10, 15));
      expect(ExpenseMath.balance([...list, s], me, partner), 0);
    });

    test('when I owe, I pay, and the balance zeroes for both sides', () {
      final list = [
        expense(amount: 999, paidBy: partner),
        expense(amount: 12345, paidBy: partner, split: ExpenseSplit.full),
        expense(amount: 300),
      ];
      final balance = ExpenseMath.balance(list, me, partner);
      expect(balance, isNegative);
      final s = ExpenseMath.settlement(
        balance: balance,
        myUid: me,
        partnerUid: partner,
        on: DateTime(2026, 10, 15),
      )!;
      expect(s.paidBy, me);
      expect(s.amountMinor, -balance);
      final after = [...list, s];
      expect(ExpenseMath.balance(after, me, partner), 0);
      expect(ExpenseMath.balance(after, partner, me), 0);
    });

    test('a settlement read back from Firestore still zeroes it', () {
      final list = [expense(amount: 777)];
      final s = ExpenseMath.settlement(
        balance: ExpenseMath.balance(list, me, partner),
        myUid: me,
        partnerUid: partner,
        on: DateTime(2026, 10, 15),
      )!;
      final stored = Expense.fromMap('s1', s.toMap());
      expect(ExpenseMath.balance([...list, stored], me, partner), 0);
    });

    test('nothing to settle when square', () {
      expect(
        ExpenseMath.settlement(
          balance: 0,
          myUid: me,
          partnerUid: partner,
          on: DateTime(2026),
        ),
        isNull,
      );
    });
  });

  group('totals and grouping', () {
    final list = [
      expense(id: 'a', amount: 1000, spentOn: DateTime(2026, 10, 2)),
      expense(
        id: 'b',
        amount: 2500,
        category: ExpenseCategory.groceries,
        spentOn: DateTime(2026, 10, 9),
      ),
      expense(
        id: 'c',
        amount: 500,
        category: ExpenseCategory.food,
        spentOn: DateTime(2026, 10, 9),
        createdAt: DateTime(2026, 10, 9, 8),
      ),
      expense(
        id: 's',
        amount: 9999,
        kind: ExpenseKind.settlement,
        spentOn: DateTime(2026, 10, 10),
      ),
      expense(
        id: 'd',
        amount: 4000,
        category: ExpenseCategory.travel,
        spentOn: DateTime(2026, 9, 30),
      ),
    ];

    test('groups by month, newest first, settlements excluded from totals', () {
      final months = ExpenseMath.byMonth(list);
      expect(months.map((m) => '${m.year}-${m.month}'), ['2026-10', '2026-9']);
      expect(months.first.items.map((e) => e.id), ['s', 'b', 'c', 'a']);
      expect(months.first.totalMinor, 4000);
      expect(months.last.totalMinor, 4000);
    });

    test('pending rows (no createdAt) sort first within a day', () {
      final ids = ExpenseMath.sorted(list).map((e) => e.id).toList();
      expect(ids.indexOf('b') < ids.indexOf('c'), isTrue);
    });

    test('monthly totals by category, largest first', () {
      final oct = ExpenseMath.monthlyByCategory(list, 2026, 10);
      expect(oct.map((t) => t.category), [
        ExpenseCategory.groceries,
        ExpenseCategory.food,
      ]);
      expect(oct.map((t) => t.totalMinor), [2500, 1500]);
      expect(ExpenseMath.monthlyByCategory(list, 2026, 8), isEmpty);
    });
  });

  group('parsing amounts', () {
    test('accepts grouped and decimal input', () {
      expect(ExpenseMath.parseAmount('1,250.50'), 125050);
      expect(ExpenseMath.parseAmount('1,25,000'), 12500000);
      expect(ExpenseMath.parseAmount(' 1250 '), 125000);
      expect(ExpenseMath.parseAmount('0.5'), 50);
      expect(ExpenseMath.parseAmount('.05'), 5);
      expect(ExpenseMath.parseAmount('12.'), 1200);
      expect(ExpenseMath.parseAmount('0.01'), 1);
      // No floating-point drift.
      expect(ExpenseMath.parseAmount('0.29'), 29);
      expect(ExpenseMath.parseAmount('1.15'), 115);
    });

    test('rejects zero, negatives, junk and too many decimals', () {
      for (final bad in [
        '',
        '0',
        '0.00',
        '-5',
        '-0.01',
        'abc',
        '1.2.3',
        '12.345',
        '.',
        '₹100',
        '1e3',
      ]) {
        expect(ExpenseMath.parseAmount(bad), isNull, reason: bad);
      }
    });

    test('rejects amounts over the limit', () {
      expect(ExpenseMath.parseAmount('1,00,00,000'), Expense.maxAmountMinor);
      expect(ExpenseMath.parseAmount('10000000.01'), isNull);
      expect(ExpenseMath.parseAmount('99999999999999999999'), isNull);
    });

    test('shares allow zero and empty', () {
      expect(ExpenseMath.parseShare(''), 0);
      expect(ExpenseMath.parseShare('0'), 0);
      expect(ExpenseMath.parseShare('250.5'), 25050);
      expect(ExpenseMath.parseShare('-1'), isNull);
    });

    test('explains what is wrong', () {
      expect(ExpenseMath.amountError('', 'INR'), 'Enter an amount');
      expect(ExpenseMath.amountError('0', 'INR'), 'Enter an amount above zero');
      expect(
        ExpenseMath.amountError('-3', 'INR'),
        'Enter an amount above zero',
      );
      expect(
        ExpenseMath.amountError('1.234', 'INR'),
        'Use at most 2 decimal places',
      );
      expect(ExpenseMath.amountError('2,00,00,000', 'INR'), contains('under'));
      expect(ExpenseMath.amountError('1,250.50', 'INR'), isNull);
    });

    test('toInput round-trips through parseAmount', () {
      expect(ExpenseMath.toInput(125050), '1250.50');
      expect(ExpenseMath.toInput(125000), '1250');
      expect(ExpenseMath.toInput(5), '0.05');
      for (final m in [1, 99, 100, 125050, Expense.maxAmountMinor]) {
        expect(ExpenseMath.parseAmount(ExpenseMath.toInput(m)), m);
      }
    });
  });

  group('formatting', () {
    test('INR uses the rupee sign and lakh grouping', () {
      expect(ExpenseMath.format(125000, 'INR'), '₹1,250');
      expect(ExpenseMath.format(125050, 'INR'), '₹1,250.50');
      expect(ExpenseMath.format(12500000, 'INR'), '₹1,25,000');
      expect(ExpenseMath.format(5, 'INR'), '₹0.05');
      expect(ExpenseMath.symbolFor('INR'), '₹');
    });

    test('USD uses the dollar sign and thousands grouping', () {
      expect(ExpenseMath.format(125050, 'USD'), r'$1,250.50');
      expect(ExpenseMath.format(12500000, 'USD'), r'$125,000');
      expect(ExpenseMath.symbolFor('USD'), r'$');
    });

    test('other currencies format without crashing', () {
      for (final c in ExpenseMath.currencies) {
        expect(ExpenseMath.format(123456, c), contains('1,234.56'));
        expect(ExpenseMath.currencyNames[c], isNotNull);
      }
      expect(ExpenseMath.format(100, 'EUR'), '€1');
      expect(ExpenseMath.format(100, 'GBP'), '£1');
      // Dollar-like currencies are told apart.
      expect(ExpenseMath.format(100, 'SGD'), r'S$1');
      expect(ExpenseMath.format(250, 'AUD'), r'A$2.50');
      expect(ExpenseMath.format(100, 'CAD'), r'C$1');
      expect(ExpenseMath.format(100, 'AED'), 'AED 1');
      expect(ExpenseMath.symbolFor('AED'), 'AED');
    });
  });

  group('screens', () {
    testWidgets('balance in plain words, settle up records a settlement', (
      tester,
    ) async {
      final now = DateTime.now();
      final service = await pumpScreen(
        tester,
        const ExpensesScreen(),
        expenses: [
          expense(id: 'a', amount: 250000, spentOn: now),
          expense(
            id: 'b',
            amount: 1500,
            paidBy: partner,
            category: ExpenseCategory.groceries,
            spentOn: now,
          ),
        ],
      );
      expect(find.text('Ravi owes you'), findsOneWidget);
      expect(find.text('₹1,242.50'), findsOneWidget);
      expect(find.text('This month by category'), findsOneWidget);

      await tester.tap(find.text('Settle up'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ravi paid you ₹1,242.50'), findsOneWidget);
      await tester.tap(find.text('Record payment'));
      await tester.pumpAndSettle();

      expect(service.saved, hasLength(1));
      final s = service.saved.single;
      expect(s.isSettlement, isTrue);
      expect(s.paidBy, partner);
      expect(s.amountMinor, 124250);
    });

    testWidgets('empty list shows a friendly hint and the add button', (
      tester,
    ) async {
      await pumpScreen(tester, const ExpensesScreen());
      expect(find.textContaining('No shared expenses yet'), findsOneWidget);
      expect(find.text('Add expense'), findsOneWidget);
    });

    testWidgets('editor previews shares and saves a custom split', (
      tester,
    ) async {
      final service = await pumpScreen(tester, const ExpenseEditorScreen());

      await tester.enterText(find.byType(TextFormField).first, '1,001');
      await tester.enterText(find.byType(TextFormField).at(1), 'Dinner');
      await tester.pumpAndSettle();
      expect(find.text('Ravi will owe you ₹500.50'), findsOneWidget);

      await tester.tap(find.text('In full'));
      await tester.pumpAndSettle();
      expect(find.text('Ravi will owe you ₹1,001'), findsOneWidget);

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      final mine = find.widgetWithText(TextFormField, 'Your share');
      await tester.enterText(mine, '200.25');
      await tester.pumpAndSettle();
      // The other share fills in so they add up exactly.
      expect(find.text('800.75'), findsOneWidget);
      expect(find.text('Ravi will owe you ₹800.75'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = service.saved.single;
      expect(saved.amountMinor, 100100);
      expect(saved.split, ExpenseSplit.custom);
      expect(saved.shares, {me: 20025, partner: 80075});
      expect(saved.title, 'Dinner');
      expect(saved.createdBy, me);
    });

    testWidgets('editor refuses custom shares that do not add up', (
      tester,
    ) async {
      final service = await pumpScreen(tester, const ExpenseEditorScreen());
      await tester.enterText(find.byType(TextFormField).first, '100');
      await tester.enterText(find.byType(TextFormField).at(1), 'Cab');
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ravi\'s share'),
        '10',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Your share'),
        '50',
      );
      // A share over the total can't be balanced by the other field, so
      // the shares no longer add up.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ravi\'s share'),
        '150',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(service.saved, isEmpty);
      expect(find.textContaining('Shares add up to'), findsOneWidget);
    });

    testWidgets('editor rejects a zero amount', (tester) async {
      final service = await pumpScreen(tester, const ExpenseEditorScreen());
      await tester.enterText(find.byType(TextFormField).first, '0');
      await tester.enterText(find.byType(TextFormField).at(1), 'Nothing');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an amount above zero'), findsOneWidget);
      expect(service.saved, isEmpty);
    });
  });
}
