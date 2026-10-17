import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:couple_app/features/plans/models/date_plan.dart';

/// What kind of place it is.
enum PlaceCategory {
  restaurant('restaurant', 'Restaurant', '🍽️', Icons.restaurant),
  cafe('cafe', 'Café', '☕', Icons.local_cafe_outlined),
  bar('bar', 'Bar', '🍸', Icons.local_bar_outlined),
  outdoors('outdoors', 'Outdoors', '🌳', Icons.park_outlined),
  travel('travel', 'Travel', '🧳', Icons.luggage_outlined),
  shopping('shopping', 'Shopping', '🛍️', Icons.shopping_bag_outlined),
  activity('activity', 'Activity', '🎳', Icons.attractions_outlined),
  other('other', 'Other', '📍', Icons.place_outlined);

  const PlaceCategory(this.id, this.label, this.emoji, this.icon);
  final String id;
  final String label;
  final String emoji;
  final IconData icon;

  static PlaceCategory fromId(String? id) {
    for (final c in values) {
      if (c.id == id) return c;
    }
    return PlaceCategory.other;
  }

  /// The date vibe that fits a place like this, for "Plan a date here".
  DateVibe get vibe => switch (this) {
    restaurant => DateVibe.food,
    cafe => DateVibe.cozy,
    bar => DateVibe.fancy,
    outdoors => DateVibe.outdoors,
    travel => DateVibe.adventure,
    shopping => DateVibe.cozy,
    activity => DateVibe.adventure,
    other => DateVibe.cozy,
  };
}

/// Whether you still want to go or have been.
enum PlaceStatus {
  wantToGo('wantToGo', 'Want to go'),
  been('been', 'Been there');

  const PlaceStatus(this.id, this.label);
  final String id;
  final String label;

  static PlaceStatus fromId(String? id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return PlaceStatus.wantToGo;
  }
}

/// A place you want to go together, or have been.
/// Stored at `couples/{coupleId}/places/{placeId}`.
class Place {
  static const maxName = 120;
  static const maxArea = 200;
  static const maxMapsUrl = 2000;
  static const maxNotes = 2000;

  final String id;
  final String name;

  /// Address or neighbourhood.
  final String area;

  /// A link to the place in a maps app, or ''.
  final String mapsUrl;

  final PlaceCategory category;
  final PlaceStatus status;

  /// 1–5, once you've been.
  final int? rating;

  /// The day you went (local midnight).
  final DateTime? visitedAt;

  final String notes;
  final bool favourite;
  final String createdBy;
  final DateTime? createdAt;

  const Place({
    required this.id,
    required this.name,
    required this.createdBy,
    this.area = '',
    this.mapsUrl = '',
    this.category = PlaceCategory.other,
    this.status = PlaceStatus.wantToGo,
    this.rating,
    this.visitedAt,
    this.notes = '',
    this.favourite = false,
    this.createdAt,
  });

  bool get isBeen => status == PlaceStatus.been;

  /// Where "Open in Maps" goes: the saved link if it's a web link, else a
  /// Google Maps search for the name and area.
  String get openInMapsUrl =>
      isWebUrl(mapsUrl) ? mapsUrl.trim() : mapsSearchUrl(name, area);

  /// Name and area joined for display or search ("Toit, Indiranagar").
  String get label => joinNameAndArea(name, area);

  factory Place.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Place.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});

  /// Builds a place from stored fields, tolerating missing or malformed
  /// ones.
  static Place fromMap(String id, Map<String, dynamic> data) {
    final status = PlaceStatus.fromId(_string(data['status']));
    final been = status == PlaceStatus.been;
    return Place(
      id: id,
      name: _string(data['name']) ?? '',
      area: _string(data['area']) ?? '',
      mapsUrl: _string(data['mapsUrl']) ?? '',
      category: PlaceCategory.fromId(_string(data['category'])),
      status: status,
      rating: been ? _rating(data['rating']) : null,
      visitedAt: been ? _date(data['visitedAt']) : null,
      notes: _string(data['notes']) ?? '',
      favourite: data['favourite'] == true,
      createdBy: _string(data['createdBy']) ?? '',
      createdAt: _date(data['createdAt']),
    );
  }

  /// Stored fields, without `createdAt` / `updatedAt` (added by the
  /// service). Rating and visit date are only kept for places you've been.
  Map<String, dynamic> toMap() {
    final visited = isBeen ? visitedAt : null;
    final url = mapsUrl.trim();
    return {
      'name': _clip(name.trim(), maxName),
      'area': _clip(area.trim(), maxArea),
      'mapsUrl': isWebUrl(url) && url.length <= maxMapsUrl ? url : '',
      'category': category.id,
      'status': status.id,
      'rating': isBeen ? rating : null,
      'visitedAt': visited == null ? null : Timestamp.fromDate(visited),
      'notes': _clip(notes.trim(), maxNotes),
      'favourite': favourite,
      'createdBy': createdBy,
    };
  }

  Place copyWith({
    String? name,
    String? area,
    String? mapsUrl,
    PlaceCategory? category,
    PlaceStatus? status,
    int? Function()? rating,
    DateTime? Function()? visitedAt,
    String? notes,
    bool? favourite,
  }) {
    return Place(
      id: id,
      name: name ?? this.name,
      area: area ?? this.area,
      mapsUrl: mapsUrl ?? this.mapsUrl,
      category: category ?? this.category,
      status: status ?? this.status,
      rating: rating == null ? this.rating : rating(),
      visitedAt: visitedAt == null ? this.visitedAt : visitedAt(),
      notes: notes ?? this.notes,
      favourite: favourite ?? this.favourite,
      createdBy: createdBy,
      createdAt: createdAt,
    );
  }

  /// A date idea for this place: "Date at Toit", located at its name and
  /// area, with a vibe that suits the category.
  DatePlan toDateIdea(String createdBy) {
    final title = 'Date at ${name.trim()}';
    final location = label;
    return DatePlan(
      id: '',
      title: _clip(title, DatePlan.maxTitle),
      location: _clip(location, DatePlan.maxLocation),
      vibe: category.vibe,
      notes: '',
      createdBy: createdBy,
    );
  }

  /// True for an http:// or https:// link with a host.
  static bool isWebUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    return (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// "Name, Area", or whichever of the two is set.
  static String joinNameAndArea(String name, String area) =>
      [name.trim(), area.trim()].where((s) => s.isNotEmpty).join(', ');

  /// A Google Maps search for [name] and [area].
  static String mapsSearchUrl(String name, String area) {
    final query = joinNameAndArea(name, area);
    return 'https://www.google.com/maps/search/?api=1&query='
        '${Uri.encodeComponent(query)}';
  }
}

/// Pure filtering and sorting for places.
class PlaceLists {
  const PlaceLists._();

  /// Places with [status], optionally only [category] and only favourites.
  ///
  /// Want to go: favourites first, then newest. Been there: most recent
  /// visit first, then favourites, then newest.
  static List<Place> filter(
    Iterable<Place> all, {
    required PlaceStatus status,
    PlaceCategory? category,
    bool favouritesOnly = false,
  }) {
    final list =
        all
            .where(
              (p) =>
                  p.status == status &&
                  (category == null || p.category == category) &&
                  (!favouritesOnly || p.favourite),
            )
            .toList()
          ..sort((a, b) {
            if (status == PlaceStatus.been) {
              final byVisit = _newestFirst(a.visitedAt, b.visitedAt);
              if (byVisit != 0) return byVisit;
            }
            if (a.favourite != b.favourite) return a.favourite ? -1 : 1;
            return _newestFirst(a.createdAt, b.createdAt);
          });
    return list;
  }

  /// How many places have each status.
  static int count(Iterable<Place> all, PlaceStatus status) =>
      all.where((p) => p.status == status).length;

  /// Categories in use, in enum order, for the filter chips.
  static List<PlaceCategory> categoriesUsed(Iterable<Place> all) {
    final used = all.map((p) => p.category).toSet();
    return PlaceCategory.values.where(used.contains).toList();
  }

  // Unsaved (null) values count as newest.
  static int _newestFirst(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    return b.compareTo(a);
  }
}

String? _string(Object? v) => v is String ? v : null;

DateTime? _date(Object? v) => switch (v) {
  final Timestamp t => t.toDate(),
  final DateTime d => d,
  _ => null,
};

int? _rating(Object? v) {
  if (v is! num || v.isNaN || v.isInfinite) return null;
  final i = v.round();
  return i >= 1 && i <= 5 ? i : null;
}

String _clip(String s, int max) => s.length <= max ? s : s.substring(0, max);
