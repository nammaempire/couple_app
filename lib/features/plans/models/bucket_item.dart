import 'package:couple_app/core/backend/backend.dart';
import 'package:flutter/material.dart';

/// What kind of dream a bucket-list item is.
enum BucketCategory {
  travel('travel', 'Travel', '✈️', Icons.flight_takeoff),
  adventure('adventure', 'Adventure', '🧗', Icons.terrain_outlined),
  food('food', 'Food', '🍜', Icons.restaurant_outlined),
  learn('learn', 'Learn', '📚', Icons.school_outlined),
  home('home', 'Home', '🏡', Icons.home_outlined),
  romance('romance', 'Romance', '💞', Icons.favorite_outline),
  other('other', 'Other', '✨', Icons.auto_awesome_outlined);

  const BucketCategory(this.id, this.label, this.emoji, this.icon);
  final String id;
  final String label;
  final String emoji;
  final IconData icon;

  static BucketCategory fromId(String? id) {
    for (final c in values) {
      if (c.id == id) return c;
    }
    return BucketCategory.other;
  }
}

/// Something the two of you want to do together someday.
class BucketItem {
  static const maxTitleLength = 120;
  static const maxNotesLength = 2000;

  final String id;
  final String title;
  final String notes;
  final BucketCategory category;
  final bool done;
  final DateTime? doneAt;

  /// Who ticked it off.
  final String? doneBy;

  /// The year you hope to have done it by, e.g. 2027.
  final int? targetYear;

  final String createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BucketItem({
    required this.id,
    required this.title,
    required this.createdBy,
    this.notes = '',
    this.category = BucketCategory.other,
    this.done = false,
    this.doneAt,
    this.doneBy,
    this.targetYear,
    this.createdAt,
    this.updatedAt,
  });

  /// Not done yet and its target year has already passed.
  bool isOverdue(DateTime now) {
    final year = targetYear;
    return !done && year != null && year < now.year;
  }

  BucketItem copyWith({
    String? title,
    String? notes,
    BucketCategory? category,
    int? targetYear,
    bool clearTargetYear = false,
  }) {
    return BucketItem(
      id: id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      category: category ?? this.category,
      done: done,
      doneAt: doneAt,
      doneBy: doneBy,
      targetYear: clearTargetYear ? null : (targetYear ?? this.targetYear),
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory BucketItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      fromMap(doc.id, doc.data() ?? <String, dynamic>{});

  /// Builds an item from stored fields, tolerating missing or odd values.
  static BucketItem fromMap(String id, Map<String, dynamic> data) {
    final done = data['done'] == true;
    final year = data['targetYear'];
    return BucketItem(
      id: id,
      title: _string(data['title']),
      notes: _string(data['notes']),
      category: BucketCategory.fromId(_nonEmpty(data['category'])),
      done: done,
      doneAt: done ? _date(data['doneAt']) : null,
      doneBy: done ? _nonEmpty(data['doneBy']) : null,
      targetYear: year is num ? year.toInt() : null,
      createdBy: _string(data['createdBy']),
      createdAt: _date(data['createdAt']),
      updatedAt: _date(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title.trim(),
    'notes': notes.trim(),
    'category': category.id,
    'done': done,
    'doneAt': doneAt == null ? null : Timestamp.fromDate(doneAt!),
    'doneBy': doneBy,
    'targetYear': targetYear,
    'createdBy': createdBy,
  };

  /// The fields an editor may change. Updates write only these, so an edit
  /// never undoes a tick your partner made meanwhile.
  Map<String, dynamic> toEditableMap() => {
    'title': title.trim(),
    'notes': notes.trim(),
    'category': category.id,
    'targetYear': targetYear,
  };

  static String _string(Object? v) => v is String ? v : '';

  static String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;

  static DateTime? _date(Object? v) => switch (v) {
    final Timestamp t => t.toDate(),
    final DateTime d => d,
    _ => null,
  };
}
