import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/know_me/know_me_bank.dart';
import 'package:couple_app/features/play/know_me/know_me_logic.dart';
import 'package:couple_app/features/play/know_me/know_me_providers.dart';
import 'package:couple_app/features/play/know_me/know_me_question.dart';
import 'package:couple_app/features/play/know_me/know_me_screen.dart';
import 'package:couple_app/features/play/know_me/know_me_service.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/providers/play_providers.dart';

const me = 'u1';
const partner = 'u2';
const gameId = 'g1';

Game quiz({
  String subject = me,
  String? turn,
  Map<String, dynamic> extra = const {},
  GameStatus status = GameStatus.active,
  int moveCount = 1,
}) {
  return Game(
    id: gameId,
    type: GameType.knowMe,
    status: status,
    createdBy: subject,
    invitee: subject == me ? partner : me,
    turn: status == GameStatus.active ? (turn ?? subject) : null,
    moveCount: moveCount,
    state: {
      ...KnowMeLogic.newState(subject: subject, random: Random(1)),
      ...extra,
    },
  );
}

/// Applies the result of [changes] to [game], like Firestore would.
Game applyChanges(Game game, Map<String, dynamic> changes) => Game(
  id: game.id,
  type: game.type,
  status: changes.containsKey('status')
      ? GameStatus.fromId(changes['status'] as String?)
      : game.status,
  createdBy: game.createdBy,
  invitee: game.invitee,
  turn: changes.containsKey('turn') ? changes['turn'] as String? : game.turn,
  state: changes.containsKey('state')
      ? Map<String, dynamic>.from(changes['state'] as Map)
      : game.state,
  winner: changes['winner'] as String?,
  moveCount: game.moveCount + 1,
);

/// Records turns, applying them to an in-memory game.
class _FakeGameService implements GameService {
  _FakeGameService(this.game);
  Game game;
  final changes = <Map<String, dynamic>>[];

  @override
  Future<void> takeTurn({
    required String coupleId,
    required String gameId,
    required String me,
    required Map<String, dynamic> Function(Game game) apply,
  }) async {
    if (game.turn != me) throw const GameMoveException('Not your turn');
    final c = apply(game);
    changes.add(c);
    game = applyChanges(game, c);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _FakeKnowMeService extends KnowMeService {
  _FakeKnowMeService({this.secret = const [], this.failRead = false});
  final List<int> secret;
  final bool failRead;
  final submitted = <List<int>>[];

  @override
  Future<void> submitAnswers({
    required String coupleId,
    required String gameId,
    required String me,
    required List<int> answers,
  }) async => submitted.add(answers);

  @override
  Future<List<int>> readAnswers({
    required String coupleId,
    required String gameId,
  }) async {
    if (failRead) throw Exception('offline');
    return secret;
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  Game game, {
  _FakeGameService? games,
  _FakeKnowMeService? knowMe,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithBuild(
          (ref, notifier) =>
              const AppUser(uid: me, displayName: 'Asha', coupleId: 'c1'),
        ),
        partnerNameProvider.overrideWithValue('Ravi'),
        gameProvider(gameId).overrideWith((ref) => Stream.value(game)),
        gameServiceProvider.overrideWithValue(games ?? _FakeGameService(game)),
        knowMeServiceProvider.overrideWithValue(knowMe ?? _FakeKnowMeService()),
      ],
      child: const MaterialApp(home: KnowMeScreen(gameId: gameId)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('question bank', () {
    test('has at least 40 questions with unique ids', () {
      expect(KnowMeBank.all.length, greaterThanOrEqualTo(40));
      final ids = KnowMeBank.all.map((q) => q.id).toSet();
      expect(ids.length, KnowMeBank.all.length);
    });

    test('every question has 4 distinct short options and both phrasings', () {
      for (final q in KnowMeBank.all) {
        expect(q.options.length, 4, reason: q.id);
        expect(q.options.toSet().length, 4, reason: q.id);
        expect(
          q.options.every((o) => o.isNotEmpty && o.length <= 30),
          isTrue,
          reason: q.id,
        );
        expect(
          q.partner,
          contains(KnowMeQuestion.namePlaceholder),
          reason: q.id,
        );
        expect(q.self, isNot(contains('{')), reason: q.id);
        expect(RegExp(r'^[a-z_]+$').hasMatch(q.id), isTrue, reason: q.id);
      }
    });

    test('byId and phrasing', () {
      final q = KnowMeBank.byId('ideal_sunday')!;
      expect(q.self, 'My ideal Sunday is…');
      expect(q.about('Asha'), 'Asha\'s ideal Sunday is…');
      expect(q.textFor(), q.self);
      expect(KnowMeBank.byId('nope'), isNull);
    });
  });

  group('newState', () {
    test('picks 7 distinct known questions', () {
      final s = KnowMeLogic.newState(subject: me, random: Random(42));
      expect(s['subject'], me);
      expect(s['total'], 7);
      final ids = s['questions'] as List<String>;
      expect(ids.length, 7);
      expect(ids.toSet().length, 7);
      expect(ids.every((id) => KnowMeBank.byId(id) != null), isTrue);
    });

    test('is deterministic for a seeded Random and varies by seed', () {
      final a = KnowMeLogic.newState(subject: me, random: Random(7));
      final b = KnowMeLogic.newState(subject: me, random: Random(7));
      final c = KnowMeLogic.newState(subject: me, random: Random(8));
      expect(a['questions'], b['questions']);
      expect(a['questions'], isNot(c['questions']));
    });

    test('first turn is the subject', () {
      expect(KnowMeLogic.firstTurn(quiz(subject: partner)), partner);
    });
  });

  group('scoring', () {
    test('counts matching positions', () {
      expect(KnowMeLogic.score([0, 1, 2, 3], [0, 1, 2, 3]), 4);
      expect(KnowMeLogic.score([0, 1, 2, 3], [3, 2, 1, 0]), 0);
      expect(
        KnowMeLogic.score([0, 1, 2, 3, 0, 1, 2], [0, 0, 2, 0, 0, 1, 3]),
        4,
      );
      expect(KnowMeLogic.score([1, 1], [1]), 1);
    });

    test('verdict tiers for 7 questions', () {
      String v(int s) => KnowMeLogic.verdict(s, 7).title;
      expect(v(7), 'Soulmate level');
      expect(v(6), 'You really know them');
      expect(v(5), 'You really know them');
      expect(v(4), 'Getting there');
      expect(v(3), 'Getting there');
      expect(v(2), 'Time for a date night of questions');
      expect(v(0), 'Time for a date night of questions');
    });
  });

  group('turn flow', () {
    final answers = [0, 1, 2, 3, 0, 1, 2];
    final guesses = [0, 1, 2, 0, 0, 1, 3];

    test('subject submits answers: turn passes to the guesser', () {
      final g = quiz();
      expect(KnowMeLogic.phaseOf(g), KnowMePhase.answering);
      final c = KnowMeLogic.submitAnswers(g, me, answers);
      expect(c['turn'], partner);
      final state = c['state'] as Map<String, dynamic>;
      expect(state['answered'], isTrue);
      expect(state.containsKey('answers'), isFalse, reason: 'stays secret');
      expect(state['subject'], me);
      expect(KnowMeLogic.phaseOf(applyChanges(g, c)), KnowMePhase.guessing);
    });

    test('invalid answer submissions are rejected', () {
      final g = quiz();
      expect(
        () => KnowMeLogic.submitAnswers(g, partner, answers),
        throwsA(isA<GameMoveException>()),
      );
      expect(
        () => KnowMeLogic.submitAnswers(g, me, [0, 1]),
        throwsA(isA<GameMoveException>()),
      );
      expect(
        () => KnowMeLogic.submitAnswers(g, me, [0, 1, 2, 3, 4, 0, 0]),
        throwsA(isA<GameMoveException>()),
      );
      final answered = quiz(turn: partner, extra: {'answered': true});
      expect(
        () => KnowMeLogic.submitAnswers(answered, me, answers),
        throwsA(isA<GameMoveException>()),
      );
    });

    test('guesser locks guesses, then reveals and finishes', () {
      var g = quiz(turn: partner, extra: {'answered': true});
      final lock = KnowMeLogic.lockGuesses(g, partner, guesses);
      expect(lock['turn'], partner);
      g = applyChanges(g, lock);
      expect(KnowMeLogic.phaseOf(g), KnowMePhase.revealing);
      expect(KnowMeLogic.guesses(g), guesses);
      expect(
        () => KnowMeLogic.lockGuesses(g, partner, answers),
        throwsA(isA<GameMoveException>()),
      );

      final reveal = KnowMeLogic.reveal(g, partner, answers);
      expect(reveal['status'], 'finished');
      expect(reveal['turn'], isNull);
      expect(reveal['winner'], isNull);
      g = applyChanges(g, reveal);
      expect(KnowMeLogic.phaseOf(g), KnowMePhase.finished);
      expect(KnowMeLogic.answers(g), answers);
      expect(KnowMeLogic.guesses(g), guesses, reason: 'guesses unchanged');
      expect(KnowMeLogic.scoreOf(g), 5);
    });

    test('subject cannot guess and guesses need answers first', () {
      final notAnswered = quiz(turn: partner);
      expect(
        () => KnowMeLogic.lockGuesses(notAnswered, partner, guesses),
        throwsA(isA<GameMoveException>()),
      );
      final answered = quiz(turn: partner, extra: {'answered': true});
      expect(
        () => KnowMeLogic.lockGuesses(answered, me, guesses),
        throwsA(isA<GameMoveException>()),
      );
      expect(
        () => KnowMeLogic.reveal(answered, partner, answers),
        throwsA(isA<GameMoveException>()),
      );
    });
  });

  group('screen', () {
    testWidgets('subject answers every question and sends them', (
      tester,
    ) async {
      final knowMe = _FakeKnowMeService();
      final game = quiz();
      await _pumpScreen(tester, game, knowMe: knowMe);

      final questions = KnowMeLogic.questionsOf(game)!;
      expect(find.text('Answer about yourself'), findsOneWidget);
      expect(find.text('1/7'), findsOneWidget);
      expect(find.text(questions.first.self), findsOneWidget);

      for (var i = 0; i < 7; i++) {
        // Pick option B for even questions, A for odd.
        await tester.tap(find.text(questions[i].options[i.isEven ? 1 : 0]));
        await tester.pumpAndSettle();
        await tester.tap(find.text(i == 6 ? 'Review' : 'Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Review'), findsOneWidget);

      // Go back from the review and change the last answer.
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('7/7'), findsOneWidget);
      await tester.tap(find.text(questions[6].options[3]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send answers'));
      await tester.pumpAndSettle();
      expect(knowMe.submitted, [
        [1, 0, 1, 0, 1, 0, 3],
      ]);
    });

    testWidgets('guesser sees questions about the partner, guesses, and '
        'the result is revealed', (tester) async {
      final game = quiz(subject: partner, turn: me, extra: {'answered': true});
      final games = _FakeGameService(game);
      final knowMe = _FakeKnowMeService(secret: [0, 0, 0, 0, 0, 0, 1]);
      await _pumpScreen(tester, game, games: games, knowMe: knowMe);

      final questions = KnowMeLogic.questionsOf(game)!;
      expect(find.text('Guess Ravi\'s answers'), findsOneWidget);
      expect(find.text(questions.first.about('Ravi')), findsOneWidget);

      for (var i = 0; i < 7; i++) {
        await tester.tap(find.text(questions[i].options[0]));
        await tester.pumpAndSettle();
        await tester.tap(find.text(i == 6 ? 'Review' : 'Next'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Lock in guesses'));
      await tester.pumpAndSettle();

      expect(games.changes, hasLength(2));
      expect((games.changes[0]['state'] as Map)['guessesLocked'], isTrue);
      expect(games.changes[0]['turn'], me);
      expect(games.changes[1]['status'], 'finished');
      expect((games.changes[1]['state'] as Map)['score'], 6);
      expect((games.changes[1]['state'] as Map)['answers'], [
        0,
        0,
        0,
        0,
        0,
        0,
        1,
      ]);
    });

    testWidgets('waiting states name the partner', (tester) async {
      await _pumpScreen(tester, quiz(subject: partner, turn: partner));
      expect(find.text('Ravi is answering about themselves…'), findsOneWidget);
    });

    testWidgets('subject waits while the partner guesses', (tester) async {
      await _pumpScreen(tester, quiz(turn: partner, extra: {'answered': true}));
      expect(find.text('Ravi is guessing your answers…'), findsOneWidget);
    });

    testWidgets('offers a reveal retry when the reveal write failed', (
      tester,
    ) async {
      final game = quiz(
        subject: partner,
        turn: me,
        extra: {
          'answered': true,
          'guesses': [0, 0, 0, 0, 0, 0, 0],
          'guessesLocked': true,
        },
      );
      final games = _FakeGameService(game);
      final failing = _FakeKnowMeService(failRead: true);
      await _pumpScreen(tester, game, games: games, knowMe: failing);

      await tester.tap(find.text('Reveal results'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not reveal the results. Check your connection.'),
        findsOneWidget,
      );
      expect(games.changes, isEmpty);
    });

    testWidgets('reveal shows the score, verdict and each answer', (
      tester,
    ) async {
      final game = quiz(
        status: GameStatus.finished,
        extra: {
          'answered': true,
          'guessesLocked': true,
          'answers': [0, 1, 2, 3, 0, 1, 2],
          'guesses': [0, 1, 2, 0, 0, 1, 3],
          'score': 5,
        },
      );
      await _pumpScreen(tester, game);

      expect(find.text('5 / 7'), findsOneWidget);
      expect(find.text('You really know them'), findsOneWidget);
      expect(find.text('Ravi guessed 5 of your 7 answers'), findsOneWidget);
      final first = KnowMeLogic.questionsOf(game)!.first;
      expect(find.text(first.self), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsWidgets);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close_rounded), findsWidgets);
    });

    testWidgets('fits a 360 wide screen', (tester) async {
      await _pumpScreen(tester, quiz());
      tester.view.physicalSize = const Size(360, 640);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
