import 'package:cloud_firestore/cloud_firestore.dart';

enum MemoryMediaType { image, video }

/// One photo or video inside a memory.
class MemoryMedia {
  final MemoryMediaType type;

  /// The photo, or the video file.
  final String url;

  /// For videos: a JPEG frame to show in grids. Photos use [url].
  final String? thumbUrl;

  final double? aspectRatio;
  final int? durationMs;

  const MemoryMedia({
    required this.type,
    required this.url,
    this.thumbUrl,
    this.aspectRatio,
    this.durationMs,
  });

  bool get isVideo => type == MemoryMediaType.video;

  /// What to show in a grid or cover: the photo itself or the video frame.
  String? get previewUrl => isVideo ? thumbUrl : url;

  static MemoryMedia? fromMap(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final url = raw['url'] as String?;
    if (url == null) return null;
    return MemoryMedia(
      type: raw['type'] == 'video'
          ? MemoryMediaType.video
          : MemoryMediaType.image,
      url: url,
      thumbUrl: raw['thumbUrl'] as String?,
      aspectRatio: (raw['aspectRatio'] as num?)?.toDouble(),
      durationMs: (raw['durationMs'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
    'type': isVideo ? 'video' : 'image',
    'url': url,
    if (thumbUrl != null) 'thumbUrl': thumbUrl,
    if (aspectRatio != null) 'aspectRatio': aspectRatio,
    if (durationMs != null) 'durationMs': durationMs,
  };
}

/// A shared moment: photos and videos with a title, date, place and album.
class Memory {
  final String id;
  final String title;
  final String caption;

  /// When it happened (not when it was added).
  final DateTime date;

  final String? place;
  final String album;
  final List<MemoryMedia> media;
  final bool favorite;
  final String createdBy;
  final DateTime? createdAt;

  const Memory({
    required this.id,
    required this.title,
    required this.date,
    required this.album,
    required this.createdBy,
    this.caption = '',
    this.place,
    this.media = const [],
    this.favorite = false,
    this.createdAt,
  });

  /// The first photo or video frame, used as the cover.
  String? get coverUrl {
    for (final m in media) {
      final url = m.previewUrl;
      if (url != null) return url;
    }
    return null;
  }

  int get photoCount => media.where((m) => !m.isVideo).length;
  int get videoCount => media.where((m) => m.isVideo).length;

  /// Case-insensitive match against title, caption, place and album.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) ||
        caption.toLowerCase().contains(q) ||
        (place?.toLowerCase().contains(q) ?? false) ||
        album.toLowerCase().contains(q);
  }

  factory Memory.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final place = (data['place'] as String?)?.trim();
    return Memory(
      id: doc.id,
      title: (data['title'] as String?) ?? '',
      caption: (data['caption'] as String?) ?? '',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      place: (place == null || place.isEmpty) ? null : place,
      album: (data['album'] as String?) ?? MemoryAlbums.randomMoments,
      media: ((data['media'] as List<dynamic>?) ?? const [])
          .map(MemoryMedia.fromMap)
          .whereType<MemoryMedia>()
          .toList(),
      favorite: (data['favorite'] as bool?) ?? false,
      createdBy: (data['createdBy'] as String?) ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// The built-in albums. Couples can add their own names on top.
class MemoryAlbums {
  const MemoryAlbums._();

  static const firstDate = 'First Date';
  static const trips = 'Trips';
  static const birthdays = 'Birthdays';
  static const anniversaries = 'Anniversaries';
  static const randomMoments = 'Random Moments';

  static const defaults = [
    firstDate,
    trips,
    birthdays,
    anniversaries,
    randomMoments,
  ];

  static String emojiFor(String album) => switch (album) {
    firstDate => '💘',
    trips => '✈️',
    birthdays => '🎂',
    anniversaries => '💍',
    randomMoments => '✨',
    _ => '📁',
  };

  /// Default albums first, then any custom ones used, alphabetically.
  static List<String> all(Iterable<Memory> memories) {
    final custom =
        memories
            .map((m) => m.album)
            .where((a) => !defaults.contains(a))
            .toSet()
            .toList()
          ..sort();
    return [...defaults, ...custom];
  }
}

/// A summary of the memories in one month or year, for "Our Memories".
class MemoryRecap {
  final String label;
  final List<Memory> memories;

  const MemoryRecap({required this.label, required this.memories});

  bool get isEmpty => memories.isEmpty;
  int get photoCount => memories.fold(0, (total, m) => total + m.photoCount);
  int get videoCount => memories.fold(0, (total, m) => total + m.videoCount);

  /// Distinct places, most visited first.
  List<String> get places {
    final counts = <String, int>{};
    for (final m in memories) {
      final p = m.place;
      if (p != null) counts[p] = (counts[p] ?? 0) + 1;
    }
    final list = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return list;
  }

  /// The album with the most memories, if any.
  String? get topAlbum {
    final counts = <String, int>{};
    for (final m in memories) {
      counts[m.album] = (counts[m.album] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  /// Up to [count] preview images, favourites first, oldest to newest.
  List<String> highlights([int count = 6]) {
    final sorted = [...memories]
      ..sort((a, b) {
        if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
        return a.date.compareTo(b.date);
      });
    final urls = <String>[];
    for (final m in sorted) {
      for (final media in m.media) {
        final url = media.previewUrl;
        if (url != null) urls.add(url);
        if (urls.length >= count) return urls;
      }
    }
    return urls;
  }

  static MemoryRecap month(Iterable<Memory> all, int year, int month) {
    final list =
        all.where((m) => m.date.year == year && m.date.month == month).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return MemoryRecap(label: '${names[month - 1]} $year', memories: list);
  }

  static MemoryRecap year(Iterable<Memory> all, int year) {
    final list = all.where((m) => m.date.year == year).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return MemoryRecap(label: '$year', memories: list);
  }

  /// Memories from this calendar day in earlier years ("On this day").
  static List<Memory> onThisDay(Iterable<Memory> all, DateTime today) {
    return all
        .where(
          (m) =>
              m.date.month == today.month &&
              m.date.day == today.day &&
              m.date.year < today.year,
        )
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }
}
