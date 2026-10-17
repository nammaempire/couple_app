import 'dart:math';

import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/know_me/know_me_bank.dart';
import 'package:couple_app/features/play/know_me/know_me_question.dart';
import 'package:couple_app/features/play/models/game.dart';

/// Where a quiz is up to. Exactly one person acts in each active phase.
enum KnowMePhase {
  /// The subject answers about themselves. Turn: subject.
  answering,

  /// The partner guesses the subject's answers. Turn: guesser.
  guessing,

  /// Guesses are locked in; the guesser still has to reveal the answers
  /// (normally done straight away, retried if that write failed).
  /// Turn: guesser.
  revealing,

  /// Answers, guesses and score are all in the game. Turn: none.
  finished,
}

/// How the score feels, for the reveal screen.
class KnowMeVerdict {
  const KnowMeVerdict(this.emoji, this.title);
  final String emoji;
  final String title;
}

/// The rules of "How well do you know me?".
///
/// The subject (the inviter) answers 7 questions about themselves; their
/// answers go to a secret doc only they can read. The partner then guesses,
/// locks their guesses in, reads the secret and reveals the result.
///
/// State keys (all in `game.state`):
/// - `subject` (String): uid of the person being guessed about; never changes.
/// - `questions` (`List<String>`): question ids from [KnowMeBank], in order.
/// - `total` (int): number of questions (7).
/// - `answered` (bool): the subject has submitted their answers.
/// - `guesses` (`List<int>`): the guesser's option indexes; set with
///   `guessesLocked` and frozen after.
/// - `guessesLocked` (bool): the guesser has submitted.
/// - `answers` (`List<int>`): the subject's option indexes, copied in from
///   the secret doc at the reveal.
/// - `score` (int): how many guesses matched, set at the reveal.
class KnowMeLogic {
  const KnowMeLogic._();

  static const questionCount = 7;
  static const optionCount = 4;

  /// Starting state; [subject] is the person the quiz is about.
  static Map<String, dynamic> newState({
    required String subject,
    Random? random,
  }) => {
    'subject': subject,
    'questions': pickQuestions(random ?? Random()),
    'total': questionCount,
  };

  /// Who acts first once the invite is accepted: the subject answers.
  static String firstTurn(Game game) => subjectOf(game);

  /// [count] distinct question ids from the bank, in random order.
  static List<String> pickQuestions(
    Random random, {
    int count = questionCount,
  }) {
    final pool = [for (final q in KnowMeBank.all) q.id];
    // Partial Fisher-Yates: the first [count] slots end up a random sample.
    for (var i = 0; i < count; i++) {
      final j = i + random.nextInt(pool.length - i);
      final tmp = pool[i];
      pool[i] = pool[j];
      pool[j] = tmp;
    }
    return pool.sublist(0, count);
  }

  // ---- Reading the state ----------------------------------------------

  static String subjectOf(Game game) =>
      (game.state['subject'] as String?) ?? game.createdBy;

  static String guesserOf(Game game) => game.opponentOf(subjectOf(game));

  static List<String> questionIds(Game game) =>
      _strings(game.state['questions']);

  /// The game's questions, or null if any id is unknown to this version.
  static List<KnowMeQuestion>? questionsOf(Game game) {
    final ids = questionIds(game);
    if (ids.isEmpty) return null;
    final questions = [for (final id in ids) KnowMeBank.byId(id)];
    if (questions.contains(null)) return null;
    return questions.cast<KnowMeQuestion>();
  }

  static bool isAnswered(Game game) => game.state['answered'] == true;
  static bool guessesLocked(Game game) => game.state['guessesLocked'] == true;
  static List<int> guesses(Game game) => _ints(game.state['guesses']);
  static List<int> answers(Game game) => _ints(game.state['answers']);

  static int scoreOf(Game game) =>
      (game.state['score'] as num?)?.toInt() ??
      score(answers(game), guesses(game));

  static int totalOf(Game game) =>
      (game.state['total'] as num?)?.toInt() ?? questionIds(game).length;

  static KnowMePhase phaseOf(Game game) {
    if (game.isFinished) return KnowMePhase.finished;
    if (guessesLocked(game)) return KnowMePhase.revealing;
    if (isAnswered(game)) return KnowMePhase.guessing;
    return KnowMePhase.answering;
  }

  // ---- Scoring --------------------------------------------------------

  /// How many guesses match the answers, position by position.
  static int score(List<int> answers, List<int> guesses) {
    var n = 0;
    for (var i = 0; i < min(answers.length, guesses.length); i++) {
      if (answers[i] == guesses[i]) n++;
    }
    return n;
  }

  static KnowMeVerdict verdict(int score, int total) {
    if (total > 0 && score >= total) {
      return const KnowMeVerdict('💞', 'Soulmate level');
    }
    final ratio = total == 0 ? 0 : score / total;
    if (ratio >= 0.7) return const KnowMeVerdict('🥰', 'You really know them');
    if (ratio >= 0.4) return const KnowMeVerdict('🌱', 'Getting there');
    return const KnowMeVerdict('🍿', 'Time for a date night of questions');
  }

  // ---- Moves ----------------------------------------------------------

  /// Whether [picks] is one valid option index per question.
  static bool validPicks(List<int> picks, int count) =>
      picks.length == count && picks.every((p) => p >= 0 && p < optionCount);

  /// The subject submits their answers: the game fields to change. The
  /// answers themselves go to the secret doc in the same write (see
  /// KnowMeService); they never appear in the game until the reveal.
  static Map<String, dynamic> submitAnswers(
    Game game,
    String me,
    List<int> answers,
  ) {
    if (!game.isActive) {
      throw const GameMoveException('This game has already ended.');
    }
    if (game.turn != me) {
      throw const GameMoveException('It\'s not your turn yet.');
    }
    if (subjectOf(game) != me || isAnswered(game)) {
      throw const GameMoveException('Your answers are already in.');
    }
    if (!validPicks(answers, questionIds(game).length)) {
      throw const GameMoveException('Answer every question first.');
    }
    return {
      'state': {...game.state, 'answered': true},
      'turn': guesserOf(game),
    };
  }

  /// The guesser locks in their guesses. The turn stays with them so they
  /// can reveal the answers next.
  static Map<String, dynamic> lockGuesses(
    Game game,
    String me,
    List<int> guesses,
  ) {
    if (guesserOf(game) != me || !isAnswered(game)) {
      throw const GameMoveException('It\'s not time to guess yet.');
    }
    if (guessesLocked(game)) {
      throw const GameMoveException('Your guesses are already in.');
    }
    if (!validPicks(guesses, questionIds(game).length)) {
      throw const GameMoveException('Guess every question first.');
    }
    return {
      'state': {...game.state, 'guesses': guesses, 'guessesLocked': true},
      'turn': me,
    };
  }

  /// The guesser reveals [answers] (read from the secret doc) and the game
  /// finishes. Nobody "wins" a quiz about each other.
  static Map<String, dynamic> reveal(Game game, String me, List<int> answers) {
    if (guesserOf(game) != me || !guessesLocked(game)) {
      throw const GameMoveException('Lock in your guesses first.');
    }
    if (!validPicks(answers, questionIds(game).length)) {
      throw const GameMoveException('Those answers don\'t fit this quiz.');
    }
    return {
      'state': {
        ...game.state,
        'answers': answers,
        'score': score(answers, guesses(game)),
      },
      'status': GameStatus.finished.id,
      'turn': null,
      'winner': null,
    };
  }

  /// Parses the secret doc's `answers`.
  static List<int> parseAnswers(Object? raw) => _ints(raw);

  static List<String> _strings(Object? v) => v is List
      ? [
          for (final e in v)
            if (e is String) e,
        ]
      : const [];

  static List<int> _ints(Object? v) => v is List
      ? [
          for (final e in v)
            if (e is num) e.toInt(),
        ]
      : const [];
}
