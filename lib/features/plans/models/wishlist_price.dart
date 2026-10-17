import 'package:couple_app/features/plans/models/expense_math.dart';

/// Parsing and formatting wishlist prices, kept in integer minor units.
class WishlistPrice {
  const WishlistPrice._();

  /// ₹1 crore in paise.
  static const maxMinor = 1000000000;

  /// Parses "1,250.50" → 125050 and "" → null. Returns
  /// [WishlistPriceParse.invalid] for anything else: letters, negatives,
  /// more than two decimals, or over [maxMinor]. Zero is allowed (free).
  static WishlistPriceParse parse(String input) {
    final t = input.replaceAll(',', '').replaceAll(' ', '').trim();
    if (t.isEmpty) return const WishlistPriceParse._(null, true);
    final match = RegExp(r'^(\d+)(?:\.(\d{0,2}))?$').firstMatch(t);
    if (match == null) return WishlistPriceParse.invalid;
    final whole = match.group(1)!;
    // Guard before int.parse so huge inputs cannot overflow.
    if (whole.length > 10) return WishlistPriceParse.invalid;
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    final minor = int.parse(whole) * 100 + int.parse(fraction);
    if (minor > maxMinor) return WishlistPriceParse.invalid;
    return WishlistPriceParse._(minor, true);
  }

  /// "₹1,250" or "₹1,250.50" in [currency]. Whole amounts drop the decimals.
  static String format(int minor, String currency) {
    return ExpenseMath.format(minor, currency);
  }

  /// The plain number for an edit field: 125050 → "1250.50", 125000 → "1250".
  static String toInput(int? minor) {
    if (minor == null) return '';
    final whole = minor ~/ 100;
    final rest = minor % 100;
    return rest == 0 ? '$whole' : '$whole.${rest.toString().padLeft(2, '0')}';
  }

  /// Just the symbol for a prefix, e.g. "₹".
  static String symbol(String currency) => ExpenseMath.symbolFor(currency);
}

/// The result of [WishlistPrice.parse].
class WishlistPriceParse {
  const WishlistPriceParse._(this.minor, this.isValid);

  static const invalid = WishlistPriceParse._(null, false);

  /// The amount in minor units, or null for an empty field.
  final int? minor;
  final bool isValid;
}
