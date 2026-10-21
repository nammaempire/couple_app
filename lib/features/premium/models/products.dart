/// What a product does once the server grants it.
enum ProductKind {
  /// Premium for the couple, renewing (`premium_monthly`, `premium_yearly`).
  subscription,

  /// One memory book credit (`book_single`). Consumed after it is granted.
  book,

  /// Premium given to the partner (`gift_premium_*`). Consumed.
  giftPremium,

  /// A memory book given to the partner (`gift_book`). Consumed.
  giftBook,
}

/// The Play Console products, and what each one is.
class Products {
  const Products._();

  static const premiumMonthly = 'premium_monthly';
  static const premiumYearly = 'premium_yearly';
  static const bookSingle = 'book_single';
  static const giftPremium1m = 'gift_premium_1m';
  static const giftPremium3m = 'gift_premium_3m';
  static const giftPremium12m = 'gift_premium_12m';
  static const giftBook = 'gift_book';

  static const subscriptions = {premiumMonthly, premiumYearly};
  static const gifts = [giftPremium1m, giftPremium3m, giftPremium12m, giftBook];
  static const all = {...subscriptions, bookSingle, ...gifts};

  /// The app's Android package, sent with every purchase to the server.
  static const packageName = 'com.nammaempire.together';

  /// Longest gift message.
  static const maxGiftMessage = 300;

  static ProductKind kindOf(String id) => switch (id) {
    premiumMonthly || premiumYearly => ProductKind.subscription,
    bookSingle => ProductKind.book,
    giftBook => ProductKind.giftBook,
    _ => ProductKind.giftPremium,
  };

  /// Bought once and used up: consumed after the server grants it, so it
  /// can be bought again.
  static bool isConsumable(String id) => kindOf(id) != ProductKind.subscription;

  static bool isGift(String id) => gifts.contains(id);

  /// Months of Premium in a premium gift.
  static int? giftMonths(String id) => switch (id) {
    giftPremium1m => 1,
    giftPremium3m => 3,
    giftPremium12m => 12,
    _ => null,
  };

  /// A short name for screens, used until the store's title arrives.
  static String label(String id) => switch (id) {
    premiumMonthly => 'Monthly',
    premiumYearly => 'Yearly',
    bookSingle => 'Memory book',
    giftPremium1m => '1 month of Premium',
    giftPremium3m => '3 months of Premium',
    giftPremium12m => '12 months of Premium',
    giftBook => 'A Memory book',
    _ => id,
  };
}

/// A product as the store sells it here: its localized price.
class StoreProduct {
  const StoreProduct({
    required this.id,
    required this.title,
    required this.price,
    this.rawPrice,
    this.currencyCode,
  });

  final String id;
  final String title;

  /// Localized, e.g. `₹199.00`.
  final String price;
  final double? rawPrice;
  final String? currencyCode;
}
