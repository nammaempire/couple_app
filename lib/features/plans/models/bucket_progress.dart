import 'package:couple_app/features/plans/models/bucket_item.dart';

/// Pure counting, filtering and ordering for the bucket list.
class BucketProgress {
  const BucketProgress._(this.done, this.total);

  final int done;
  final int total;

  int get remaining => total - done;

  /// 0.0–1.0; 0 when the list is empty.
  double get fraction => total == 0 ? 0 : done / total;

  /// Whole-number percentage, rounded down so 99.6% never reads as 100%.
  int get percent => (fraction * 100).floor();

  bool get isComplete => total > 0 && done == total;

  /// "12 of 40 done".
  String get label => '$done of $total done';

  static BucketProgress of(Iterable<BucketItem> items) {
    var done = 0;
    var total = 0;
    for (final item in items) {
      total++;
      if (item.done) done++;
    }
    return BucketProgress._(done, total);
  }

  /// Items in [category], or every item when it is null.
  static List<BucketItem> filter(
    Iterable<BucketItem> items,
    BucketCategory? category,
  ) => category == null
      ? items.toList()
      : items.where((i) => i.category == category).toList();

  /// How many items each category has, for the filter chips.
  static Map<BucketCategory, int> countByCategory(Iterable<BucketItem> items) {
    final counts = <BucketCategory, int>{};
    for (final item in items) {
      counts[item.category] = (counts[item.category] ?? 0) + 1;
    }
    return counts;
  }

  /// Still to do: items with a target year first (soonest first), then the
  /// rest, newest first. Unsaved items (no createdAt yet) count as newest.
  static List<BucketItem> toDo(Iterable<BucketItem> items) {
    final list = items.where((i) => !i.done).toList()
      ..sort((a, b) {
        final ya = a.targetYear;
        final yb = b.targetYear;
        if (ya != null && yb != null && ya != yb) return ya.compareTo(yb);
        if ((ya == null) != (yb == null)) return ya == null ? 1 : -1;
        return _newestFirst(a.createdAt, b.createdAt);
      });
    return list;
  }

  /// Ticked off, most recently done first.
  static List<BucketItem> completed(Iterable<BucketItem> items) {
    return items.where((i) => i.done).toList()
      ..sort((a, b) => _newestFirst(a.doneAt, b.doneAt));
  }

  static int _newestFirst(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    return b.compareTo(a);
  }
}
