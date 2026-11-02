import 'dart:async';

import 'package:couple_app/core/backend/backend.dart';

import 'package:couple_app/features/home/models/daily_question.dart';

/// Handles the once-a-day shared prompt.
///
/// Stored at `couples/{coupleId}/dailyQuestions/{yyyy-MM-dd}`. Both answers
/// live in one document so a single stream drives the unlock state.
class DailyQuestionService {
  DailyQuestionService({
    Db? db,
    DateTime Function()? clock,
    this.dayCheckInterval = const Duration(minutes: 1),
  }) : _db = db ?? Db.instance,
       _now = clock ?? DateTime.now;

  final Db _db;
  final DateTime Function() _now;

  /// How often an open stream checks whether the day has changed (a timer
  /// set for midnight can fire late after the phone has slept).
  final Duration dayCheckInterval;

  DocumentReference<Map<String, dynamic>> _docFor(
    String coupleId,
    String dateKey,
  ) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('dailyQuestions')
        .doc(dateKey);
  }

  /// Today's question and whatever has been answered so far. Moves on to
  /// the next day's question at midnight (this phone's time) while open.
  Stream<DailyQuestionEntry> watchToday(String coupleId) {
    // Closed by its listener cancelling (onCancel stops everything).
    // ignore: close_sinks
    late final StreamController<DailyQuestionEntry> out;
    StreamSubscription<DailyQuestionEntry>? sub;
    Timer? dayCheck;
    String? watching;

    void follow() {
      final today = _now();
      final dateKey = QuestionBank.dateKeyFor(today);
      if (dateKey == watching) return;
      watching = dateKey;
      final prompt = QuestionBank.promptFor(today, coupleId);
      unawaited(sub?.cancel());
      sub = _docFor(coupleId, dateKey)
          .snapshots()
          .map((doc) {
            if (!doc.exists) {
              return DailyQuestionEntry(dateKey: dateKey, prompt: prompt);
            }
            return DailyQuestionEntry.fromDoc(doc, prompt);
          })
          .listen(out.add, onError: out.addError);
    }

    out = StreamController<DailyQuestionEntry>(
      onListen: () {
        follow();
        dayCheck = Timer.periodic(dayCheckInterval, (_) => follow());
      },
      onCancel: () async {
        dayCheck?.cancel();
        await sub?.cancel();
      },
    );
    return out.stream;
  }

  /// Saves this partner's answer to the question they were shown
  /// ([entry]), even if midnight passed while they typed. The prompt is
  /// written alongside so the history stays readable even if the bank
  /// changes later.
  Future<void> answer({
    required String coupleId,
    required String uid,
    required String text,
    DailyQuestionEntry? entry,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final today = _now();
    final dateKey = entry?.dateKey ?? QuestionBank.dateKeyFor(today);
    final prompt = entry?.prompt ?? QuestionBank.promptFor(today, coupleId);

    await _docFor(coupleId, dateKey).set({
      'prompt': prompt,
      'date': dateKey,
      'answers': {
        uid: {'text': trimmed, 'answeredAt': Timestamp.now()},
      },
    }, SetOptions(merge: true));
  }

  /// Past days where both partners answered, newest first.
  Stream<List<DailyQuestionEntry>> watchHistory(
    String coupleId, {
    int limit = 60,
  }) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('dailyQuestions')
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => DailyQuestionEntry.fromDoc(doc, ''))
              .where((entry) => entry.isUnlocked)
              .toList(),
        );
  }
}
