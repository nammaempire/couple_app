import 'package:cloud_firestore/cloud_firestore.dart';

/// One partner's answer to a daily question.
class DailyAnswer {
  final String uid;
  final String text;
  final DateTime? answeredAt;

  const DailyAnswer({required this.uid, required this.text, this.answeredAt});
}

/// The shared state of one day's question: the prompt plus both answers.
///
/// Answers stay hidden until both partners have replied, so neither can be
/// influenced by the other's words.
class DailyQuestionEntry {
  /// Document id, formatted `yyyy-MM-dd`.
  final String dateKey;
  final String prompt;
  final Map<String, DailyAnswer> answers;

  const DailyQuestionEntry({
    required this.dateKey,
    required this.prompt,
    this.answers = const {},
  });

  bool hasAnswered(String uid) => answers.containsKey(uid);

  /// Both partners have replied, so the answers can be revealed.
  bool get isUnlocked => answers.length >= 2;

  DailyAnswer? answerFor(String uid) => answers[uid];

  factory DailyQuestionEntry.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String fallbackPrompt,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final rawAnswers =
        (data['answers'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    final parsed = <String, DailyAnswer>{};
    rawAnswers.forEach((uid, value) {
      final map = (value as Map<String, dynamic>?) ?? <String, dynamic>{};
      parsed[uid] = DailyAnswer(
        uid: uid,
        text: (map['text'] as String?) ?? '',
        answeredAt: (map['answeredAt'] as Timestamp?)?.toDate(),
      );
    });

    return DailyQuestionEntry(
      dateKey: doc.id,
      prompt: (data['prompt'] as String?) ?? fallbackPrompt,
      answers: parsed,
    );
  }
}

/// The prompt bank. A question is chosen deterministically from the date and
/// the couple id, so both phones show the same one without server coordination.
class QuestionBank {
  const QuestionBank._();

  static const prompts = <String>[
    'What is something small I did recently that made you happy?',
    'Where would you take me if money were no object?',
    'What is your favourite memory of us so far?',
    'What song reminds you of me?',
    'What do you think I am best at?',
    'What is something you want us to try together this year?',
    'When did you first know you liked me?',
    'What does a perfect lazy Sunday with me look like?',
    'What is one thing you wish I asked you about more often?',
    'What are you looking forward to most right now?',
    'What is something you find attractive about me that is not physical?',
    'What is a habit of mine that makes you smile?',
    'If we could relive one day together, which would you pick?',
    'What is something you are proud of me for?',
    'What do you need more of from me lately?',
    'What is the nicest thing anyone has ever done for you?',
    'What would our ideal home look like?',
    'What is a small thing that made you happy today?',
    'What do you think we are best at as a couple?',
    'What is something you have never told me?',
    'Which trip should we take next, and why?',
    'What is your favourite photo of us?',
    'What is one thing you want to learn together?',
    'How do you like to be comforted when you are upset?',
    'What made you laugh hardest recently?',
    'What tradition should we start?',
    'What do you hope is true about us in five years?',
    'What is your love language, and do you think I speak it well?',
    'What is a compliment you have been holding on to?',
    'What is the best advice about love you have heard?',
    'What is something I do that makes you feel safe?',
  ];

  /// Same prompt for both partners, rotating daily.
  static String promptFor(DateTime date, String coupleId) {
    final dayNumber = DateTime(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime(2020)).inDays;
    final seed = dayNumber + coupleId.hashCode.abs();
    return prompts[seed % prompts.length];
  }

  /// Consecutive days, ending today or yesterday, on which both partners
  /// answered. [answeredDateKeys] are `yyyy-MM-dd` keys of unlocked days.
  /// Yesterday still counts so the streak does not look broken before
  /// today's question has been answered.
  static int streak(Iterable<String> answeredDateKeys, DateTime today) {
    final keys = answeredDateKeys.toSet();
    var day = DateTime(today.year, today.month, today.day);
    if (!keys.contains(dateKeyFor(day))) {
      day = DateTime(day.year, day.month, day.day - 1);
    }

    var count = 0;
    while (keys.contains(dateKeyFor(day))) {
      count++;
      // Step back by calendar day; DST-safe because it rebuilds the date.
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return count;
  }

  static String dateKeyFor(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
