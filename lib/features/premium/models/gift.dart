import 'package:couple_app/core/backend/backend.dart';

/// What a gift is.
enum GiftKind { premium, book }

/// A gift from one partner to the other: `couples/{cid}/gifts/{id}`,
/// written by the server when the purchase is verified.
class Gift {
  const Gift({
    required this.id,
    required this.fromUid,
    required this.toUid,
    required this.kind,
    this.months,
    this.message = '',
    this.createdAt,
    this.openedAt,
  });

  final String id;
  final String fromUid;
  final String toUid;
  final GiftKind kind;

  /// Months of Premium, for premium gifts.
  final int? months;

  /// The buyer's personal message (up to 300 characters).
  final String message;
  final DateTime? createdAt;

  /// When [toUid] opened it; null until then.
  final DateTime? openedAt;

  bool get isOpened => openedAt != null;

  /// "3 months of Premium" or "a Memory book".
  String get what => switch (kind) {
    GiftKind.book => 'a Memory book',
    GiftKind.premium =>
      months == 1 ? '1 month of Premium' : '${months ?? 1} months of Premium',
  };

  factory Gift.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return Gift(
      id: doc.id,
      fromUid: (d['fromUid'] as String?) ?? '',
      toUid: (d['toUid'] as String?) ?? '',
      kind: d['kind'] == 'book' ? GiftKind.book : GiftKind.premium,
      months: (d['months'] as num?)?.toInt(),
      message: (d['message'] as String?) ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      openedAt: (d['openedAt'] as Timestamp?)?.toDate(),
    );
  }
}
