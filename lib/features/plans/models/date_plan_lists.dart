import 'dart:math';

import 'package:intl/intl.dart';

import 'package:couple_app/features/plans/models/date_plan.dart';
import 'package:couple_app/features/plans/models/expense_math.dart';

/// Pure sorting, grouping and picking for date plans.
class DatePlanLists {
  const DatePlanLists._();

  /// Ideas, newest first. Ideas still being saved (no server time yet)
  /// count as newest.
  static List<DatePlan> ideas(Iterable<DatePlan> all) {
    final list = all.where((p) => p.isIdea).toList()
      ..sort((a, b) => _newestFirst(a.createdAt, b.createdAt));
    return list;
  }

  /// Planned dates still ahead, soonest first.
  static List<DatePlan> upcoming(Iterable<DatePlan> all, DateTime now) {
    final list = all.where((p) => p.isPlanned && !p.needsRecap(now)).toList()
      ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
    return list;
  }

  /// Planned dates whose time has passed but aren't marked done ("How did
  /// it go?"), oldest first.
  static List<DatePlan> needsRecap(Iterable<DatePlan> all, DateTime now) {
    final list = all.where((p) => p.needsRecap(now)).toList()
      ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
    return list;
  }

  /// Every planned date: upcoming first (soonest first), then the past ones.
  static List<DatePlan> planned(Iterable<DatePlan> all, DateTime now) => [
    ...upcoming(all, now),
    ...needsRecap(all, now),
  ];

  /// Done dates, most recently completed first. Falls back to the
  /// scheduled time for older documents without `completedAt`.
  static List<DatePlan> done(Iterable<DatePlan> all) {
    final list = all.where((p) => p.isDone).toList()
      ..sort(
        (a, b) => _newestFirst(
          a.completedAt ?? a.scheduledAt ?? a.createdAt,
          b.completedAt ?? b.scheduledAt ?? b.createdAt,
        ),
      );
    return list;
  }

  /// A random idea for "Surprise me", or null when there are none. Avoids
  /// picking [previousId] again when there is anything else to pick.
  static DatePlan? surprise(
    List<DatePlan> ideas,
    Random random, {
    String? previousId,
  }) {
    if (ideas.isEmpty) return null;
    final pool = ideas.length > 1
        ? ideas.where((p) => p.id != previousId).toList()
        : ideas;
    return pool[random.nextInt(pool.length)];
  }

  /// "Today", "Tomorrow", "In 5 days", "In 3 weeks" for an upcoming date.
  static String countdown(DateTime at, DateTime now) {
    final day = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    final days = day.difference(today).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    if (days < 14) return 'In $days days';
    if (days < 60) return 'In ${(days / 7).floor()} weeks';
    return DateFormat.MMMd().format(at);
  }

  static int _newestFirst(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    return b.compareTo(a);
  }
}

/// Parsing and showing money amounts kept in minor units (paise).
class DatePlanCost {
  const DatePlanCost._();

  static final _pattern = RegExp(r'^\d+(\.\d{1,2})?$');

  /// "1,250.50" → 125050, "0" → 0. Null for empty, malformed, negative or
  /// over [DatePlan.maxCostMinor] input.
  static int? parseMinor(String input) {
    final text = input.replaceAll(',', '').replaceAll(' ', '').trim();
    if (text.isEmpty || !_pattern.hasMatch(text)) return null;
    final parts = text.split('.');
    // Longer than any allowed amount, and would overflow int.
    if (parts[0].length > 10) return null;
    final whole = int.tryParse(parts[0]);
    if (whole == null) return null;
    final fraction = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
    final minor = whole * 100 + int.parse(fraction);
    return minor > DatePlan.maxCostMinor ? null : minor;
  }

  /// The amount for an input field: "1250.5" style, no grouping.
  static String toInput(int minor) {
    final whole = minor ~/ 100;
    final fraction = minor % 100;
    if (fraction == 0) return '$whole';
    return '$whole.${fraction.toString().padLeft(2, '0')}';
  }

  /// "₹1,250" or "₹1,250.50"; "Free" for zero.
  static String format(int minor, String currency) {
    if (minor == 0) return 'Free';
    return ExpenseMath.format(minor, currency);
  }

  static String symbol(String currency) => ExpenseMath.symbolFor(currency);
}
