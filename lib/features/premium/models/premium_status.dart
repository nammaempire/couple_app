import 'package:cloud_firestore/cloud_firestore.dart';

/// The couple's Premium (`couples/{cid}.premium`), written only by the
/// server. One purchase covers both partners.
class PremiumStatus {
  const PremiumStatus({
    required this.until,
    required this.plan,
    this.subscriptionUntil,
    this.giftUntil,
    this.source,
    this.updatedAt,
  });

  final DateTime until;

  /// `monthly`, `yearly` or `gift`.
  final String plan;
  final DateTime? subscriptionUntil;
  final DateTime? giftUntil;
  final String? source;
  final DateTime? updatedAt;

  bool isActive(DateTime now) => until.isAfter(now);

  /// A renewing subscription is running. Gifting months of Premium on top
  /// of one could be partly lost when it renews, so it isn't offered.
  bool hasActiveSubscription(DateTime now) =>
      (plan == 'monthly' || plan == 'yearly') &&
      (subscriptionUntil?.isAfter(now) ?? false);

  static PremiumStatus? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final until = raw['until'];
    if (until is! Timestamp) return null;
    DateTime? date(String key) {
      final v = raw[key];
      return v is Timestamp ? v.toDate() : null;
    }

    final plan = raw['plan'];
    final source = raw['source'];
    return PremiumStatus(
      until: until.toDate(),
      plan: plan is String ? plan : 'monthly',
      subscriptionUntil: date('subscriptionUntil'),
      giftUntil: date('giftUntil'),
      source: source is String ? source : null,
      updatedAt: date('updatedAt'),
    );
  }
}
