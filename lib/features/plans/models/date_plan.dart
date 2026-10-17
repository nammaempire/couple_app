import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:couple_app/features/together/models/calendar_event.dart';

/// Where a date plan is: an idea, on the calendar, or done.
enum DatePlanStatus {
  idea('idea', 'Ideas', Icons.lightbulb_outline),
  planned('planned', 'Planned', Icons.event_outlined),
  done('done', 'Done', Icons.favorite_outline);

  const DatePlanStatus(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;

  static DatePlanStatus fromId(String? id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return DatePlanStatus.idea;
  }
}

/// The feel of a date.
enum DateVibe {
  cozy('cozy', 'Cozy', '🕯️'),
  adventure('adventure', 'Adventure', '🧗'),
  fancy('fancy', 'Fancy', '🥂'),
  outdoors('outdoors', 'Outdoors', '🌿'),
  food('food', 'Food', '🍜'),
  culture('culture', 'Culture', '🎭'),
  surprise('surprise', 'Surprise', '🎁');

  const DateVibe(this.id, this.label, this.emoji);
  final String id;
  final String label;
  final String emoji;

  static DateVibe fromId(String? id) {
    for (final v in values) {
      if (v.id == id) return v;
    }
    return DateVibe.cozy;
  }
}

/// A date idea, a planned date or one you've been on.
/// Stored at `couples/{coupleId}/datePlans/{planId}`.
class DatePlan {
  static const maxTitle = 120;
  static const maxNotes = 2000;
  static const maxLocation = 200;
  static const maxReflection = 2000;

  /// ₹1 crore (or the same number in another currency), in minor units.
  static const maxCostMinor = 1000000000;

  final String id;
  final String title;
  final String notes;
  final DatePlanStatus status;

  /// When it's planned for. Set for planned dates and kept once done.
  final DateTime? scheduledAt;

  final String location;

  /// Rough cost in minor units (paise). Null when unknown, 0 when free.
  final int? estimatedCostMinor;

  final DateVibe vibe;

  /// 1–5 hearts, once done.
  final int? rating;

  /// How it went, once done.
  final String reflection;

  final String createdBy;
  final DateTime? createdAt;
  final DateTime? completedAt;

  const DatePlan({
    required this.id,
    required this.title,
    required this.createdBy,
    this.notes = '',
    this.status = DatePlanStatus.idea,
    this.scheduledAt,
    this.location = '',
    this.estimatedCostMinor,
    this.vibe = DateVibe.cozy,
    this.rating,
    this.reflection = '',
    this.createdAt,
    this.completedAt,
  });

  bool get isIdea => status == DatePlanStatus.idea;
  bool get isPlanned => status == DatePlanStatus.planned;
  bool get isDone => status == DatePlanStatus.done;

  /// Planned for a time that has passed but not marked done yet.
  bool needsRecap(DateTime now) {
    final at = scheduledAt;
    return isPlanned && at != null && at.isBefore(now);
  }

  factory DatePlan.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      DatePlan.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});

  /// Builds a plan from stored fields. Missing or malformed fields fall back
  /// to safe defaults, so old or partial documents never crash.
  static DatePlan fromMap(String id, Map<String, dynamic> data) {
    final status = DatePlanStatus.fromId(_string(data['status']));
    final scheduledAt = _date(data['scheduledAt']);
    return DatePlan(
      id: id,
      title: _string(data['title']) ?? '',
      notes: _string(data['notes']) ?? '',
      // A "planned" date without a date can't be shown as planned.
      status: status == DatePlanStatus.planned && scheduledAt == null
          ? DatePlanStatus.idea
          : status,
      scheduledAt: scheduledAt,
      location: _string(data['location']) ?? '',
      estimatedCostMinor: _cost(data['estimatedCostMinor']),
      vibe: DateVibe.fromId(_string(data['vibe'])),
      rating: _rating(data['rating']),
      reflection: _string(data['reflection']) ?? '',
      createdBy: _string(data['createdBy']) ?? '',
      createdAt: _date(data['createdAt']),
      completedAt: _date(data['completedAt']),
    );
  }

  /// Stored fields, without `createdAt` / `updatedAt` (the service adds
  /// those as server timestamps).
  Map<String, dynamic> toMap() {
    final at = scheduledAt;
    final done = completedAt;
    return {
      'title': _clip(title.trim(), maxTitle),
      'notes': _clip(notes.trim(), maxNotes),
      'status': status.id,
      'scheduledAt': at == null ? null : Timestamp.fromDate(at),
      'location': _clip(location.trim(), maxLocation),
      'estimatedCostMinor': estimatedCostMinor,
      'vibe': vibe.id,
      'rating': rating,
      'reflection': _clip(reflection.trim(), maxReflection),
      'createdBy': createdBy,
      'completedAt': done == null ? null : Timestamp.fromDate(done),
    };
  }

  DatePlan copyWith({
    String? title,
    String? notes,
    DatePlanStatus? status,
    DateTime? Function()? scheduledAt,
    String? location,
    int? Function()? estimatedCostMinor,
    DateVibe? vibe,
    int? Function()? rating,
    String? reflection,
    DateTime? Function()? completedAt,
  }) {
    return DatePlan(
      id: id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      scheduledAt: scheduledAt == null ? this.scheduledAt : scheduledAt(),
      location: location ?? this.location,
      estimatedCostMinor: estimatedCostMinor == null
          ? this.estimatedCostMinor
          : estimatedCostMinor(),
      vibe: vibe ?? this.vibe,
      rating: rating == null ? this.rating : rating(),
      reflection: reflection ?? this.reflection,
      createdBy: createdBy,
      createdAt: createdAt,
      completedAt: completedAt == null ? this.completedAt : completedAt(),
    );
  }

  /// The calendar entry for a scheduled plan (planned or done), or null for
  /// an idea with no date.
  CalendarEvent? toCalendarEvent() {
    final at = scheduledAt;
    if (at == null || isIdea) return null;
    final place = location.trim();
    return CalendarEvent(
      id: '${CalendarEvent.datePlanIdPrefix}$id',
      title: title.trim().isEmpty ? 'Date night' : title.trim(),
      type: EventType.dateNight,
      start: at,
      allDay: false,
      location: place.isEmpty ? null : place,
      notes: notes.trim(),
      reminder: status == DatePlanStatus.planned
          ? ReminderOption.hour
          : ReminderOption.none,
      isAutomatic: true,
      createdBy: createdBy,
    );
  }
}

String? _string(Object? v) => v is String ? v : null;

DateTime? _date(Object? v) => switch (v) {
  final Timestamp t => t.toDate(),
  final DateTime d => d,
  _ => null,
};

int? _cost(Object? v) {
  if (v is! num || v.isNaN || v.isInfinite) return null;
  final i = v.round();
  return i < 0 ? null : i;
}

int? _rating(Object? v) {
  if (v is! num || v.isNaN || v.isInfinite) return null;
  final i = v.round();
  return i >= 1 && i <= 5 ? i : null;
}

String _clip(String s, int max) => s.length <= max ? s : s.substring(0, max);
