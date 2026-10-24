import 'package:couple_app/core/backend/backend.dart';

import 'package:couple_app/features/home/models/daily_question.dart';

/// Handles the once-a-day shared prompt.
///
/// Stored at `couples/{coupleId}/dailyQuestions/{yyyy-MM-dd}`. Both answers
/// live in one document so a single stream drives the unlock state.
class DailyQuestionService {
  DailyQuestionService({Db? db}) : _db = db ?? Db.instance;

  final Db _db;

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

  /// Today's question and whatever has been answered so far.
  Stream<DailyQuestionEntry> watchToday(String coupleId) {
    final today = DateTime.now();
    final dateKey = QuestionBank.dateKeyFor(today);
    final prompt = QuestionBank.promptFor(today, coupleId);

    return _docFor(coupleId, dateKey).snapshots().map((doc) {
      if (!doc.exists) {
        return DailyQuestionEntry(dateKey: dateKey, prompt: prompt);
      }
      return DailyQuestionEntry.fromDoc(doc, prompt);
    });
  }

  /// Saves this partner's answer. The prompt is written alongside so the
  /// history stays readable even if the bank changes later.
  Future<void> answer({
    required String coupleId,
    required String uid,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final today = DateTime.now();
    final dateKey = QuestionBank.dateKeyFor(today);

    await _docFor(coupleId, dateKey).set({
      'prompt': QuestionBank.promptFor(today, coupleId),
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
