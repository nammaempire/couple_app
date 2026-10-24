import 'package:couple_app/core/backend/backend.dart';
import 'package:flutter/material.dart';

/// How much the owner wants something. Declared in sort order.
enum WishlistPriority {
  love('love', 'Love it', '💖', Icons.favorite),
  like('like', 'Like it', '🙂', Icons.thumb_up_alt_outlined),
  someday('someday', 'Someday', '🌙', Icons.bedtime_outlined);

  const WishlistPriority(this.id, this.label, this.emoji, this.icon);
  final String id;
  final String label;
  final String emoji;
  final IconData icon;

  static WishlistPriority fromId(String? id) {
    for (final p in values) {
      if (p.id == id) return p;
    }
    return WishlistPriority.like;
  }
}

/// When the wish would make a good gift.
enum WishlistOccasion {
  any('any', 'Any time', '🎁', Icons.card_giftcard),
  birthday('birthday', 'Birthday', '🎂', Icons.cake_outlined),
  anniversary('anniversary', 'Anniversary', '💍', Icons.favorite_outline),
  festival('festival', 'Festival', '🪔', Icons.celebration_outlined);

  const WishlistOccasion(this.id, this.label, this.emoji, this.icon);
  final String id;
  final String label;
  final String emoji;
  final IconData icon;

  static WishlistOccasion fromId(String? id) {
    for (final o in values) {
      if (o.id == id) return o;
    }
    return WishlistOccasion.any;
  }
}

/// Something one of you would like. It belongs to [createdBy], the person
/// who wished for it; only they can change it.
class WishlistItem {
  static const maxTitleLength = 120;
  static const maxNotesLength = 1000;
  static const maxUrlLength = 2000;

  final String id;
  final String title;
  final String notes;

  /// '' or an http(s) link to the product.
  final String url;

  /// In minor units (paise). Null when not set.
  final int? priceMinor;

  final WishlistPriority priority;
  final WishlistOccasion occasion;

  /// The owner: the person who wants it.
  final String createdBy;

  /// The owner has it now.
  final bool received;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const WishlistItem({
    required this.id,
    required this.title,
    required this.createdBy,
    this.notes = '',
    this.url = '',
    this.priceMinor,
    this.priority = WishlistPriority.like,
    this.occasion = WishlistOccasion.any,
    this.received = false,
    this.createdAt,
    this.updatedAt,
  });

  bool get hasLink => url.isNotEmpty;

  WishlistItem copyWith({
    String? title,
    String? notes,
    String? url,
    int? priceMinor,
    bool clearPrice = false,
    WishlistPriority? priority,
    WishlistOccasion? occasion,
    bool? received,
  }) {
    return WishlistItem(
      id: id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      url: url ?? this.url,
      priceMinor: clearPrice ? null : (priceMinor ?? this.priceMinor),
      priority: priority ?? this.priority,
      occasion: occasion ?? this.occasion,
      createdBy: createdBy,
      received: received ?? this.received,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory WishlistItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      fromMap(doc.id, doc.data() ?? <String, dynamic>{});

  /// Builds an item from stored fields, tolerating missing or odd values.
  static WishlistItem fromMap(String id, Map<String, dynamic> data) {
    final price = data['priceMinor'];
    final url = data['url'];
    return WishlistItem(
      id: id,
      title: data['title'] is String ? data['title'] as String : '',
      notes: data['notes'] is String ? data['notes'] as String : '',
      // A malformed link is dropped rather than offered to open.
      url: url is String && isValidUrl(url) ? url : '',
      priceMinor: price is num && price >= 0 ? price.toInt() : null,
      priority: WishlistPriority.fromId(_str(data['priority'])),
      occasion: WishlistOccasion.fromId(_str(data['occasion'])),
      createdBy: data['createdBy'] is String ? data['createdBy'] as String : '',
      received: data['received'] == true,
      createdAt: _date(data['createdAt']),
      updatedAt: _date(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title.trim(),
    'notes': notes.trim(),
    'url': url.trim(),
    'priceMinor': priceMinor,
    'priority': priority.id,
    'occasion': occasion.id,
    'createdBy': createdBy,
    'received': received,
  };

  /// What the editor changes. Updates leave `received` and the owner alone.
  Map<String, dynamic> toEditableMap() => {
    'title': title.trim(),
    'notes': notes.trim(),
    'url': url.trim(),
    'priceMinor': priceMinor,
    'priority': priority.id,
    'occasion': occasion.id,
  };

  /// Priority (love first), then newest first. Items still being saved
  /// (no createdAt yet) count as newest.
  static List<WishlistItem> sorted(Iterable<WishlistItem> items) {
    return items.toList()..sort((a, b) {
      final byPriority = a.priority.index.compareTo(b.priority.index);
      if (byPriority != 0) return byPriority;
      final ca = a.createdAt;
      final cb = b.createdAt;
      if (ca == null && cb == null) return 0;
      if (ca == null) return -1;
      if (cb == null) return 1;
      return cb.compareTo(ca);
    });
  }

  /// '' or an absolute http(s) URL with a host, within the length limit.
  static bool isValidUrl(String url) {
    final t = url.trim();
    if (t.isEmpty) return true;
    if (t.length > maxUrlLength) return false;
    final lower = t.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return false;
    }
    final uri = Uri.tryParse(t);
    return uri != null && uri.host.isNotEmpty;
  }

  /// Tidies typed or pasted input: trims it and adds https:// when the
  /// scheme is missing ("amazon.in/x" → "https://amazon.in/x").
  static String normalizeUrl(String input) {
    final t = input.trim();
    if (t.isEmpty) return '';
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(t)) return t;
    return 'https://$t';
  }

  static String? _str(Object? v) => v is String ? v : null;

  static DateTime? _date(Object? v) => switch (v) {
    final Timestamp t => t.toDate(),
    final DateTime d => d,
    _ => null,
  };
}
