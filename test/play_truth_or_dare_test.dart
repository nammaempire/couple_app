import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/providers/play_providers.dart';
import 'package:couple_app/features/play/truth_or_dare/truth_or_dare_cards.dart';
import 'package:couple_app/features/play/truth_or_dare/truth_or_dare_logic.dart';
import 'package:couple_app/features/play/truth_or_dare/truth_or_dare_screen.dart';

const me = 'u1'; // created the game
const partner = 'u2'; // accepted: chooses first

Game game({
  Map<String, dynamic>? state,
  String? turn = partner,
  GameStatus status = GameStatus.active,
  String? winner,
}) => Game(
  id: 'g1',
  type: GameType.truthOrDare,
  status: status,
  createdBy: me,
  invitee: partner,
  turn: turn,
  state: state ?? TruthOrDareLogic.newState(),
  winner: winner,
);

/// Applies [changes] (as the transaction would) to [g].
Game applyChanges(Game g, Map<String, dynamic> changes) => Game(
  id: g.id,
  type: g.type,
  status: changes.containsKey('status')
      ? GameStatus.fromId(changes['status'] as String)
      : g.status,
  createdBy: g.createdBy,
  invitee: g.invitee,
  turn: changes.containsKey('turn') ? changes['turn'] as String? : g.turn,
  state: changes.containsKey('state')
      ? Map<String, dynamic>.from(changes['state'] as Map)
      : g.state,
  winner: changes.containsKey('winner')
      ? changes['winner'] as String?
      : g.winner,
  moveCount: g.moveCount + 1,
);

/// Records takeTurn calls and applies them to [current] without Firebase.
class _FakeGameService implements GameService {
  _FakeGameService(this.current);

  Game current;
  final calls = <Map<String, dynamic>>[];
  bool fail = false;

  @override
  Future<void> takeTurn({
    required String coupleId,
    required String gameId,
    required String me,
    required Map<String, dynamic> Function(Game game) apply,
  }) async {
    if (fail) throw Exception('offline');
    final changes = apply(current);
    calls.add({'me': me, ...changes});
    current = applyChanges(current, changes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  group('card bank', () {
    test('has at least 50 of each kind, with matching kinds', () {
      expect(TruthOrDareCards.truths.length, greaterThanOrEqualTo(50));
      expect(TruthOrDareCards.dares.length, greaterThanOrEqualTo(50));
      expect(
        TruthOrDareCards.truths.every((c) => c.kind == TruthOrDareKind.truth),
        isTrue,
      );
      expect(
        TruthOrDareCards.dares.every((c) => c.kind == TruthOrDareKind.dare),
        isTrue,
      );
    });

    test('ids are unique and texts are not duplicated', () {
      final all = [...TruthOrDareCards.truths, ...TruthOrDareCards.dares];
      expect(all.map((c) => c.id).toSet().length, all.length);
      expect(
        all.map((c) => c.text.trim().toLowerCase()).toSet().length,
        all.length,
      );
      for (final c in all) {
        expect(c.text.trim(), isNotEmpty);
        expect(TruthOrDareCards.byId(c.id), same(c));
      }
    });

    test('cards round-trip through maps', () {
      final c = TruthOrDareCards.dares.first;
      final back = TruthOrDareCard.fromMap(c.toMap())!;
      expect((back.kind, back.id, back.text), (c.kind, c.id, c.text));
      expect(TruthOrDareCard.fromMap(null), isNull);
      expect(TruthOrDareCard.fromMap({'kind': 'nope', 'id': 'x'}), isNull);
    });
  });

  group('draw', () {
    test('never repeats a used card until the pile runs out', () {
      final rng = Random(7);
      var used = <String>[];
      final seen = <String>{};
      for (var i = 0; i < TruthOrDareCards.truths.length; i++) {
        final (card, next) = TruthOrDareLogic.draw(
          TruthOrDareKind.truth,
          used,
          random: rng,
        );
        expect(card.kind, TruthOrDareKind.truth);
        expect(used, isNot(contains(card.id)));
        expect(seen.add(card.id), isTrue);
        used = next;
      }
      expect(seen.length, TruthOrDareCards.truths.length);
    });

    test('used cards of the other kind do not matter', () {
      final used = TruthOrDareCards.dares.map((c) => c.id).toList();
      final (card, next) = TruthOrDareLogic.draw(
        TruthOrDareKind.truth,
        used,
        random: Random(1),
      );
      expect(card.kind, TruthOrDareKind.truth);
      expect(next, [...used, card.id]);
    });

    test('reshuffles an empty pile, keeping the other kind used', () {
      const pile = [
        TruthOrDareCard(TruthOrDareKind.dare, 'a', 'A'),
        TruthOrDareCard(TruthOrDareKind.dare, 'b', 'B'),
      ];
      final used = ['t01', 'a', 'b'];
      for (var seed = 0; seed < 10; seed++) {
        final (card, next) = TruthOrDareLogic.draw(
          TruthOrDareKind.dare,
          used,
          random: Random(seed),
          pile: pile,
        );
        // 'b' was drawn last, so the reshuffle avoids an instant repeat.
        expect(card.id, 'a');
        expect(next, ['t01', 'a']);
      }
    });

    test('a single-card pile still draws after reshuffling', () {
      const pile = [TruthOrDareCard(TruthOrDareKind.truth, 'x', 'X')];
      final (card, next) = TruthOrDareLogic.draw(
        TruthOrDareKind.truth,
        ['x'],
        random: Random(1),
        pile: pile,
      );
      expect(card.id, 'x');
      expect(next, ['x']);
    });
  });

  group('state machine', () {
    test('new state and first turn', () {
      final s = TruthOrDareLogic.newState();
      expect(s, {
        'round': 1,
        'rounds': 10,
        'phase': 'choose',
        'chooser': null,
        'card': null,
        'used': <String>[],
        'done': <String, int>{},
        'skipped': <String, int>{},
        'history': <Map<String, dynamic>>[],
      });
      expect(TruthOrDareLogic.firstTurn(game()), partner);
      expect(TruthOrDareLogic.chooserOf(game()), partner);
      expect(TruthOrDareLogic.judgeOf(game()), me);
    });

    test('choosing draws a card and hands the turn to the judge', () {
      final changes = TruthOrDareLogic.choose(
        game(),
        partner,
        TruthOrDareKind.dare,
        random: Random(3),
      );
      expect(changes['turn'], me);
      final s = changes['state'] as Map<String, dynamic>;
      expect(s['phase'], 'judge');
      expect(s['chooser'], partner);
      expect((s['card'] as Map)['kind'], 'dare');
      expect(s['used'], [(s['card'] as Map)['id']]);
      expect(s['round'], 1);
      expect(changes.containsKey('status'), isFalse);
    });

    test('surprise me picks a kind at random', () {
      final kinds = <String>{};
      for (var seed = 0; seed < 20; seed++) {
        final s = TruthOrDareLogic.choose(
          game(),
          partner,
          null,
          random: Random(seed),
        )['state'];
        kinds.add(((s as Map)['card'] as Map)['kind'] as String);
      }
      expect(kinds, {'truth', 'dare'});
    });

    test('rejects illegal moves', () {
      expect(
        () => TruthOrDareLogic.choose(game(), me, TruthOrDareKind.truth),
        throwsA(isA<GameMoveException>()),
      );
      expect(
        () => TruthOrDareLogic.judge(game(), partner, done: true),
        throwsA(isA<GameMoveException>()),
      );
      final judging = applyChanges(
        game(),
        TruthOrDareLogic.choose(game(), partner, TruthOrDareKind.truth),
      );
      expect(
        () => TruthOrDareLogic.choose(judging, me, TruthOrDareKind.truth),
        throwsA(isA<GameMoveException>()),
      );
      expect(
        () => TruthOrDareLogic.judge(judging, partner, done: true),
        throwsA(isA<GameMoveException>()),
      );
      final finished = game(status: GameStatus.finished, turn: null);
      expect(
        () => TruthOrDareLogic.choose(finished, partner, null),
        throwsA(isA<GameMoveException>()),
      );
    });

    test('judging scores the chooser and swaps roles', () {
      var g = applyChanges(
        game(),
        TruthOrDareLogic.choose(game(), partner, TruthOrDareKind.truth),
      );
      final cardId = TruthOrDareState.of(g).card!.id;
      final changes = TruthOrDareLogic.judge(g, me, done: true);
      g = applyChanges(g, changes);
      final s = TruthOrDareState.of(g);
      expect(g.turn, me);
      expect(s.round, 2);
      expect(s.phase, 'choose');
      expect(s.chooser, me);
      expect(s.card, isNull);
      expect(s.done, {partner: 1});
      expect(s.skipped, isEmpty);
      expect(s.history, [
        {
          'round': 1,
          'chooser': partner,
          'kind': 'truth',
          'id': cardId,
          'result': 'done',
        },
      ]);
      expect(TruthOrDareLogic.chooserOf(g), me);
    });

    Game playAll(List<bool> results) {
      final rng = Random(42);
      var g = game();
      for (var i = 0; i < 10; i++) {
        final chooser = g.turn!;
        g = applyChanges(
          g,
          TruthOrDareLogic.choose(
            g,
            chooser,
            i.isEven ? TruthOrDareKind.truth : TruthOrDareKind.dare,
            random: rng,
          ),
        );
        expect(g.turn, g.opponentOf(chooser));
        g = applyChanges(
          g,
          TruthOrDareLogic.judge(g, g.turn!, done: results[i]),
        );
      }
      return g;
    }

    test('ten rounds alternate choosers, then finish', () {
      final g = playAll(List.filled(10, true));
      final s = TruthOrDareState.of(g);
      expect(g.status, GameStatus.finished);
      expect(g.turn, isNull);
      expect(s.history.length, 10);
      expect(
        s.history.map((h) => h['chooser']),
        List.generate(10, (i) => i.isEven ? partner : me),
      );
      expect(s.history.map((h) => h['round']), List.generate(10, (i) => i + 1));
      expect(s.used.toSet().length, 10);
      expect(s.done, {partner: 5, me: 5});
      expect(g.winner, isNull, reason: 'for fun: no head-to-head winner');
      expect(TruthOrDareLogic.mostDaring(g.players, s.done), Game.draw);
      expect(s.round, 10);
    });

    test('most completed cards wins', () {
      // Even rounds are the partner's, odd rounds mine.
      final g = playAll([
        true, true, true, false, true, false, false, true, true, false, //
      ]);
      final s = TruthOrDareState.of(g);
      expect(s.done, {partner: 4, me: 2});
      expect(s.skipped, {me: 3, partner: 1});
      expect(TruthOrDareLogic.mostDaring(g.players, s.done), partner);

      final g2 = playAll([
        false, true, false, true, false, true, false, true, false, true, //
      ]);
      expect(
        TruthOrDareLogic.mostDaring(g2.players, TruthOrDareState.of(g2).done),
        me,
      );
      expect(TruthOrDareState.of(g2).skipped, {partner: 5});
    });

    test('mostDaring handles missing entries', () {
      expect(TruthOrDareLogic.mostDaring([me, partner], {}), Game.draw);
      expect(TruthOrDareLogic.mostDaring([me, partner], {me: 1}), me);
      expect(TruthOrDareLogic.mostDaring([me, partner], {partner: 2}), partner);
    });

    test('history is capped', () {
      final long = List.generate(
        25,
        (i) => {
          'round': i,
          'chooser': me,
          'kind': 'truth',
          'id': 't01',
          'result': 'done',
        },
      );
      final g = game(
        turn: me,
        state: {
          ...TruthOrDareLogic.newState(),
          'round': 2,
          'phase': 'judge',
          'chooser': partner,
          'card': TruthOrDareCards.truths.first.toMap(),
          'history': long,
        },
      );
      final s = TruthOrDareLogic.judge(g, me, done: false)['state'] as Map;
      final h = s['history'] as List;
      expect(h.length, 20);
      expect((h.last as Map)['round'], 2);
    });
  });

  group('screen', () {
    const user = AppUser(uid: me, displayName: 'Asha', coupleId: 'c1');
    late _FakeGameService service;

    Widget app(Game g) {
      service = _FakeGameService(g);
      return ProviderScope(
        overrides: [
          gameServiceProvider.overrideWithValue(service),
          gameProvider('g1').overrideWith((ref) => Stream.value(g)),
          currentUserProvider.overrideWithBuild((ref, notifier) => user),
          partnerNameProvider.overrideWithValue('Ravi'),
        ],
        child: const MaterialApp(home: TruthOrDareScreen(gameId: 'g1')),
      );
    }

    Future<void> setSize(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('choose: my turn shows Truth / Dare / Surprise me', (
      tester,
    ) async {
      await setSize(tester, 360);
      await tester.pumpWidget(app(game(turn: me)));
      await tester.pumpAndSettle();
      expect(find.text('Round 1 of 10'), findsOneWidget);
      expect(find.text('Truth or dare?'), findsOneWidget);
      expect(find.text('Surprise me'), findsOneWidget);
      await tester.tap(find.text('✨ Dare'));
      await tester.pumpAndSettle();
      expect(service.calls, hasLength(1));
      expect(service.calls.single['me'], me);
      expect(service.calls.single['turn'], partner);
      final s = service.calls.single['state'] as Map;
      expect(s['phase'], 'judge');
      expect((s['card'] as Map)['kind'], 'dare');
      expect(tester.takeException(), isNull);
    });

    testWidgets('choose: waiting while Ravi chooses', (tester) async {
      await setSize(tester, 390);
      await tester.pumpWidget(app(game()));
      await tester.pump();
      expect(find.text('Ravi is choosing…'), findsOneWidget);
      expect(find.text('✨ Dare'), findsNothing);
    });

    final card = TruthOrDareCards.dares.first;
    Map<String, dynamic> judgeState(String chooser) => {
      ...TruthOrDareLogic.newState(),
      'round': 3,
      'phase': 'judge',
      'chooser': chooser,
      'card': card.toMap(),
      'used': [card.id],
      'done': {me: 1, partner: 1},
    };

    testWidgets('judge: I decide if Ravi did it', (tester) async {
      await setSize(tester, 360);
      await tester.pumpWidget(app(game(turn: me, state: judgeState(partner))));
      await tester.pumpAndSettle();
      expect(find.text('Round 3 of 10'), findsOneWidget);
      expect(find.text(card.text), findsOneWidget);
      expect(find.text('Did Ravi do it?'), findsOneWidget);
      await tester.tap(find.text('Done 💞'));
      await tester.pumpAndSettle();
      final call = service.calls.single;
      expect(call['turn'], me);
      final s = call['state'] as Map;
      expect(s['done'], {me: 1, partner: 2});
      expect(s['round'], 4);
      expect(s['phase'], 'choose');
      expect(tester.takeException(), isNull);
    });

    testWidgets('judge: waiting while Ravi decides', (tester) async {
      await setSize(tester, 390);
      await tester.pumpWidget(app(game(turn: partner, state: judgeState(me))));
      await tester.pump();
      expect(find.text(card.text), findsOneWidget);
      expect(find.text('Do it in chat or on a call'), findsOneWidget);
      expect(find.text('Ravi is deciding if you did it…'), findsOneWidget);
      expect(find.text('Done 💞'), findsNothing);
    });

    testWidgets('a failed move shows a snack bar', (tester) async {
      await setSize(tester, 390);
      await tester.pumpWidget(app(game(turn: me)));
      await tester.pumpAndSettle();
      service.fail = true;
      await tester.tap(find.text('💬 Truth'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not make that move. Check your connection.'),
        findsOneWidget,
      );
    });

    testWidgets('finished: most daring and the last cards', (tester) async {
      await setSize(tester, 360);
      final history = [
        {
          'round': 9,
          'chooser': partner,
          'kind': 'truth',
          'id': 't01',
          'result': 'done',
        },
        {
          'round': 10,
          'chooser': me,
          'kind': 'dare',
          'id': 'd02',
          'result': 'skipped',
        },
      ];
      await tester.pumpWidget(
        app(
          game(
            status: GameStatus.finished,
            turn: null,
            winner: partner,
            state: {
              ...TruthOrDareLogic.newState(),
              'round': 10,
              'done': {me: 2, partner: 4},
              'skipped': {me: 3, partner: 1},
              'history': history,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Most daring: Ravi ✨'), findsOneWidget);
      expect(find.text('4 done'), findsOneWidget);
      expect(find.text('2 done'), findsOneWidget);
      expect(find.text('3 skipped'), findsOneWidget);
      expect(find.text(TruthOrDareCards.byId('t01')!.text), findsOneWidget);
      expect(find.text(TruthOrDareCards.byId('d02')!.text), findsOneWidget);
      expect(find.text('Play again'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('finished draw', (tester) async {
      await setSize(tester, 390);
      await tester.pumpWidget(
        app(
          game(
            status: GameStatus.finished,
            turn: null,
            winner: Game.draw,
            state: {
              ...TruthOrDareLogic.newState(),
              'done': {me: 3, partner: 3},
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('You\'re both equally daring 💞'), findsOneWidget);
    });
  });
}
