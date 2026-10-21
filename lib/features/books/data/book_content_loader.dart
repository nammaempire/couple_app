import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/books/models/book.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/memories/data/memory_service.dart';
import 'package:couple_app/features/memories/models/memory.dart';
import 'package:couple_app/features/music/data/music_service.dart';
import 'package:couple_app/features/plans/data/date_plan_service.dart';
import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/together/data/love_note_service.dart';

/// Gathers a book's content from the couple's shared data, through the
/// same services the app uses.
///
/// Only memories, opened love notes, finished date plans, dates worth
/// remembering and a few counts go in. The vault and the chat are never
/// read, and a note that is still sealed or unopened is left out (its
/// words are never even fetched).
class BookContentLoader {
  BookContentLoader({
    required this.memories,
    required this.notes,
    required this.datePlans,
    required this.games,
    required this.songs,
  });

  final MemoryService memories;
  final LoveNoteService notes;
  final DatePlanService datePlans;
  final GameService games;
  final MusicService songs;

  /// Photos per memory, at most.
  static const maxPhotosPerMemory = 4;

  Future<BookContent> load({
    required Couple couple,
    required AppUser me,
    required AppUser? partner,
    required String partnerName,
    required DateTime from,
    required DateTime to,
    required String title,
    required DateTime now,
  }) async {
    bool inRange(DateTime d) => !d.isBefore(from) && !d.isAfter(to);
    final entries = <BookEntry>[];

    // Memories, with their photos (and video covers).
    final allMemories = await memories.watchMemories(couple.id).first;
    final kept = allMemories.where((m) => inRange(m.date)).toList();
    for (final m in kept) {
      final photos = <BookPhoto>[
        for (final media in m.media)
          if (media.previewUrl case final url?)
            BookPhoto(url: url, aspectRatio: media.aspectRatio),
      ];
      entries.add(
        BookMemory(
          date: m.date,
          title: m.title.trim().isEmpty ? 'A memory' : m.title.trim(),
          caption: m.caption.trim(),
          place: m.place,
          photos: photos.take(maxPhotosPerMemory).toList(),
        ),
      );
    }

    // Love notes that have arrived and been opened: words only.
    final names = {me.uid: me.displayName, ?partner?.uid: partnerName};
    var noteCount = 0;
    for (final note in await notes.watchNotes(couple.id).first) {
      if (!note.isDelivered(now) || !note.isOpened) continue;
      if (!inRange(note.deliverAt)) continue;
      try {
        final content = await notes.open(coupleId: couple.id, note: note);
        if (content.body.trim().isEmpty) continue;
        entries.add(
          BookNote(
            date: note.deliverAt,
            title: note.envelopeTitle,
            body: content.body.trim(),
            fromName: names[note.senderId] ?? partnerName,
          ),
        );
        noteCount++;
      } catch (_) {
        // Still sealed for some reason: leave it out.
      }
    }

    // Dates you marked done.
    for (final plan in await datePlans.watchPlans(couple.id).first) {
      if (!plan.isDone) continue;
      final when = plan.completedAt ?? plan.scheduledAt;
      if (when == null || !inRange(when)) continue;
      entries.add(
        BookDatePlan(
          date: when,
          title: plan.title,
          place: plan.location.trim().isEmpty ? null : plan.location.trim(),
          reflection: plan.reflection.trim(),
          rating: plan.rating,
        ),
      );
    }

    entries.addAll(
      milestones(
        couple: couple,
        me: me,
        partner: partner,
        partnerName: partnerName,
        from: from,
        to: to,
        memories: allMemories,
      ),
    );

    // Chapters by month, oldest first.
    entries.sort((a, b) => a.date.compareTo(b.date));
    final byMonth = <DateTime, List<BookEntry>>{};
    for (final e in entries) {
      byMonth.putIfAbsent(DateTime(e.date.year, e.date.month), () => []).add(e);
    }
    final months = [
      for (final MapEntry(:key, :value) in byMonth.entries)
        BookMonth(month: key, entries: value),
    ]..sort((a, b) => a.month.compareTo(b.month));

    final allGames = await games.watchGames(couple.id, limit: 1000).first;
    final allSongs = await songs.watchSongs(couple.id).first;

    return BookContent(
      title: title,
      names: '${me.displayName} & $partnerName',
      from: from,
      to: to,
      startDate: couple.startDate,
      months: months,
      numbers: BookNumbers(
        daysTogether: couple.daysTogether,
        memories: kept.length,
        notes: noteCount,
        gamesPlayed: allGames.where((g) => g.isFinished).length,
        songsSaved: allSongs.length,
      ),
    );
  }

  /// Anniversaries, both birthdays, the day you started and your first
  /// date (a memory in the "First Date" album), within the range.
  static List<BookMilestone> milestones({
    required Couple couple,
    required AppUser me,
    required AppUser? partner,
    required String partnerName,
    required DateTime from,
    required DateTime to,
    List<Memory> memories = const [],
  }) {
    final list = <BookMilestone>[];
    bool inRange(DateTime d) => !d.isBefore(from) && !d.isAfter(to);

    final start = couple.startDate;
    if (start != null) {
      if (inRange(start)) {
        list.add(BookMilestone(date: start, title: 'The day we started'));
      }
      for (var year = from.year; year <= to.year; year++) {
        final years = year - start.year;
        if (years < 1) continue;
        final day = DateTime(year, start.month, start.day);
        if (inRange(day)) {
          list.add(
            BookMilestone(
              date: day,
              title: years == 1
                  ? 'Our first anniversary'
                  : 'Our anniversary · $years years',
            ),
          );
        }
      }
    }

    void birthdays(DateTime? birthday, String name) {
      if (birthday == null) return;
      for (var year = from.year; year <= to.year; year++) {
        final day = DateTime(year, birthday.month, birthday.day);
        if (inRange(day)) {
          list.add(BookMilestone(date: day, title: '$name\'s birthday'));
        }
      }
    }

    birthdays(me.birthday, me.displayName);
    birthdays(partner?.birthday, partnerName);

    for (final m in memories) {
      if (m.album == MemoryAlbums.firstDate && inRange(m.date)) {
        list.add(BookMilestone(date: m.date, title: 'Our first date'));
        break;
      }
    }
    return list;
  }
}
