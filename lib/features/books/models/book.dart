import 'dart:typed_data';

import 'package:couple_app/core/backend/backend.dart';

/// A finished memory book: `couples/{cid}/books/{bookId}`, with its PDF at
/// [storagePath].
class MemoryBook {
  const MemoryBook({
    required this.id,
    required this.title,
    required this.createdBy,
    required this.fromDate,
    required this.toDate,
    required this.pageCount,
    required this.storagePath,
    this.createdAt,
  });

  /// Longest title the rules accept.
  static const maxTitle = 80;

  /// `couples/{cid}/books/{bookId}.pdf`.
  static String pathFor(String coupleId, String bookId) =>
      'couples/$coupleId/books/$bookId.pdf';

  final String id;
  final String title;
  final String createdBy;
  final DateTime fromDate;
  final DateTime toDate;
  final int pageCount;
  final String storagePath;
  final DateTime? createdAt;

  factory MemoryBook.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final now = DateTime.now();
    return MemoryBook(
      id: doc.id,
      title: (d['title'] as String?) ?? 'Our memory book',
      createdBy: (d['createdBy'] as String?) ?? '',
      fromDate: (d['fromDate'] as Timestamp?)?.toDate() ?? now,
      toDate: (d['toDate'] as Timestamp?)?.toDate() ?? now,
      pageCount: (d['pageCount'] as num?)?.toInt() ?? 0,
      storagePath: (d['storagePath'] as String?) ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Which stretch of time a book covers.
enum BookRange {
  thisYear('This year'),
  lastYear('Last year'),
  allTime('All time'),
  custom('Custom');

  const BookRange(this.label);
  final String label;

  /// The first and last day for this range at [now]; [start] is used for
  /// all time (the day the couple started), [custom] for custom.
  ({DateTime from, DateTime to}) dates(
    DateTime now, {
    DateTime? start,
    ({DateTime from, DateTime to})? custom,
  }) {
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return switch (this) {
      BookRange.thisYear => (from: DateTime(now.year), to: endOfToday),
      BookRange.lastYear => (
        from: DateTime(now.year - 1),
        to: DateTime(now.year - 1, 12, 31, 23, 59, 59),
      ),
      BookRange.allTime => (from: start ?? DateTime(2000), to: endOfToday),
      BookRange.custom =>
        custom == null
            ? (from: DateTime(now.year), to: endOfToday)
            : (
                from: DateTime(
                  custom.from.year,
                  custom.from.month,
                  custom.from.day,
                ),
                to: DateTime(
                  custom.to.year,
                  custom.to.month,
                  custom.to.day,
                  23,
                  59,
                  59,
                ),
              ),
    };
  }
}

/// A photo for the book: where it comes from, and once fetched, its bytes
/// (a JPEG at most 1600 px on the long edge).
class BookPhoto {
  BookPhoto({required this.url, this.aspectRatio});

  final String url;
  final double? aspectRatio;
  Uint8List? bytes;
}

/// Something that happened in a month of the book.
sealed class BookEntry {
  const BookEntry(this.date);
  final DateTime date;
}

/// A memory: its photos (up to four), caption, date and place.
class BookMemory extends BookEntry {
  const BookMemory({
    required DateTime date,
    required this.title,
    this.caption = '',
    this.place,
    this.photos = const [],
  }) : super(date);

  final String title;
  final String caption;
  final String? place;
  final List<BookPhoto> photos;
}

/// A love note that was delivered and opened: its words only.
class BookNote extends BookEntry {
  const BookNote({
    required DateTime date,
    required this.title,
    required this.body,
    required this.fromName,
  }) : super(date);

  final String title;
  final String body;
  final String fromName;
}

/// A date plan the two of you marked done.
class BookDatePlan extends BookEntry {
  const BookDatePlan({
    required DateTime date,
    required this.title,
    this.place,
    this.reflection = '',
    this.rating,
  }) : super(date);

  final String title;
  final String? place;
  final String reflection;
  final int? rating;
}

/// An anniversary, a birthday, the day you started, a first date.
class BookMilestone extends BookEntry {
  const BookMilestone({required DateTime date, required this.title})
    : super(date);

  final String title;
}

/// One month's chapter.
class BookMonth {
  const BookMonth({required this.month, required this.entries});

  /// The first of the month.
  final DateTime month;
  final List<BookEntry> entries;

  Iterable<BookMemory> get memories => entries.whereType<BookMemory>();
}

/// The numbers page.
class BookNumbers {
  const BookNumbers({
    this.daysTogether,
    this.memories = 0,
    this.notes = 0,
    this.gamesPlayed = 0,
    this.songsSaved = 0,
  });

  final int? daysTogether;
  final int memories;
  final int notes;
  final int gamesPlayed;
  final int songsSaved;
}

/// Everything that goes into a book, gathered from the couple's shared
/// data. Never the vault, the chat, or a note that hasn't been opened.
class BookContent {
  const BookContent({
    required this.title,
    required this.names,
    required this.from,
    required this.to,
    required this.months,
    required this.numbers,
    this.startDate,
    this.coverImage,
    this.avatarImages = const [],
    this.closingLine = 'Here\'s to every page we haven\'t written yet.',
  });

  final String title;

  /// "Asha & Ravi".
  final String names;
  final DateTime from;
  final DateTime to;
  final DateTime? startDate;

  /// The couple photo, if there is one (JPEG or PNG).
  final Uint8List? coverImage;

  /// Otherwise both avatars, as PNGs.
  final List<Uint8List> avatarImages;
  final List<BookMonth> months;
  final BookNumbers numbers;
  final String closingLine;

  bool get isEmpty => months.every((m) => m.entries.isEmpty);

  Iterable<BookPhoto> get photos sync* {
    for (final m in months) {
      for (final memory in m.memories) {
        yield* memory.photos;
      }
    }
  }
}
