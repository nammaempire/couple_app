import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/core/theme/app_theme.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/dice/dice_roller.dart';
import 'package:couple_app/features/play/game_catalog.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/providers/play_providers.dart';
import 'package:couple_app/features/play/snakes_ladders/snakes_ladders_logic.dart';
import 'package:couple_app/features/play/snakes_ladders/snakes_ladders_screen.dart';

const me = 'u1';
const partner = 'u2';

/// u1 invited u2; u2 accepted, so u2 rolls first.
Game game({
  Map<String, int> positions = const {me: 0, partner: 0},
  Map<String, dynamic>? lastRoll,
  int sixes = 0,
  String? turn = partner,
  GameStatus status = GameStatus.active,
  String? winner,
  int moveCount = 1,
}) => Game(
  id: 'g1',
  type: GameType.snakesLadders,
  status: status,
  createdBy: me,
  invitee: partner,
  turn: turn,
  state: {'positions': positions, 'lastRoll': lastRoll, 'sixes': sixes},
  winner: winner,
  moveCount: moveCount,
);

/// Applies [changes] to [g] the way Firestore would.
Game applied(Game g, Map<String, dynamic> changes) => Game(
  id: g.id,
  type: g.type,
  status: GameStatus.fromId(changes['status'] as String? ?? g.status.id),
  createdBy: g.createdBy,
  invitee: g.invitee,
  turn: changes.containsKey('turn') ? changes['turn'] as String? : g.turn,
  state: (changes['state'] as Map<String, dynamic>?) ?? g.state,
  winner: changes['winner'] as String? ?? g.winner,
  moveCount: g.moveCount + 1,
);

Map<String, dynamic> stateOf(Map<String, dynamic> changes) =>
    changes['state'] as Map<String, dynamic>;

Map<String, dynamic> lastRollOf(Map<String, dynamic> changes) =>
    stateOf(changes)['lastRoll'] as Map<String, dynamic>;

/// A [Random] that returns queued die faces (1–6) from `nextInt(6)`.
class _Dice implements Random {
  _Dice(this.faces);

  final List<int> faces;

  @override
  int nextInt(int max) => faces.removeAt(0) - 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Applies `takeTurn` to its game and emits the result, like a snapshot.
class _FakeGameService implements GameService {
  _FakeGameService(this.current) {
    _controller.add(current);
  }

  Game current;
  final _controller = StreamController<Game?>();
  final results = <Map<String, dynamic>>[];
  bool fail = false;

  /// Holds writes until [release], to test double taps.
  Completer<void>? hold;

  Stream<Game?> get stream => _controller.stream;

  /// Shows a change made on the partner's phone.
  void push(Game g) {
    current = g;
    _controller.add(g);
  }

  void release() => hold?.complete();

  @override
  Future<void> takeTurn({
    required String coupleId,
    required String gameId,
    required String me,
    required Map<String, dynamic> Function(Game game) apply,
  }) async {
    if (fail) throw Exception('offline');
    final changes = apply(current);
    results.add(changes);
    await hold?.future;
    push(applied(current, changes));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  group('SnakesLaddersLogic', () {
    test('new state starts both players off the board', () {
      final s = SnakesLaddersLogic.newState(inviter: me, invitee: partner);
      expect(s['positions'], {me: 0, partner: 0});
      expect(s['lastRoll'], isNull);
      expect(s['sixes'], 0);
      expect(SnakesLaddersLogic.firstTurn(game()), partner);
      expect(
        GameCatalog.newState(
          GameType.snakesLadders,
          inviter: me,
          invitee: partner,
        ),
        s,
      );
    });

    test('squares run boustrophedon from the bottom left', () {
      expect(SnakesLaddersLogic.cellOf(1), (0, 0));
      expect(SnakesLaddersLogic.cellOf(10), (0, 9));
      expect(SnakesLaddersLogic.cellOf(11), (1, 9));
      expect(SnakesLaddersLogic.cellOf(20), (1, 0));
      expect(SnakesLaddersLogic.cellOf(21), (2, 0));
      expect(SnakesLaddersLogic.cellOf(100), (9, 0));
    });

    test('the classic layout is sound', () {
      const ladders = SnakesLaddersLogic.ladders;
      const snakes = SnakesLaddersLogic.snakes;
      expect(ladders.length, 9);
      expect(snakes.length, 10);
      for (final e in ladders.entries) {
        expect(e.value, greaterThan(e.key), reason: 'ladders go up');
      }
      for (final e in snakes.entries) {
        expect(e.value, lessThan(e.key), reason: 'snakes go down');
        expect(e.key, lessThan(100));
      }
      final starts = {...ladders.keys, ...snakes.keys};
      expect(starts.length, ladders.length + snakes.length);
      for (final end in [...ladders.values, ...snakes.values]) {
        expect(starts.contains(end), isFalse, reason: 'no chains on $end');
      }
    });

    test('any roll enters the board', () {
      final m = SnakesLaddersLogic.move(0, 3);
      expect(m.to, 3);
      expect(m.via, isNull);
      expect(m.steps, [1, 2, 3]);
      // Square 1 has a ladder.
      final lucky = SnakesLaddersLogic.move(0, 1);
      expect(lucky.via, SnakesLaddersVia.ladder);
      expect((lucky.viaFrom, lucky.viaTo, lucky.to), (1, 38, 38));
    });

    test('ladders climb and snakes slide', () {
      final up = SnakesLaddersLogic.move(25, 3);
      expect(up.landing, 28);
      expect(up.to, 84);
      expect(up.via, SnakesLaddersVia.ladder);
      expect((up.viaFrom, up.viaTo), (28, 84));

      final down = SnakesLaddersLogic.move(58, 4);
      expect(down.landing, 62);
      expect(down.to, 19);
      expect(down.via, SnakesLaddersVia.snake);
      expect((down.viaFrom, down.viaTo), (62, 19));
      expect(down.steps, [59, 60, 61, 62]);
    });

    test('an overshoot bounces back off 100', () {
      final m = SnakesLaddersLogic.move(96, 5);
      expect(m.bounced, isTrue);
      expect(m.to, 99);
      expect(m.via, SnakesLaddersVia.bounce);
      expect(m.steps, [97, 98, 99, 100, 99]);

      final still = SnakesLaddersLogic.move(97, 6);
      expect(still.to, 97, reason: '103 bounces back to 97');
      expect(still.steps, [98, 99, 100, 99, 98, 97]);

      // Bouncing onto a snake's head still slides.
      final ouch = SnakesLaddersLogic.move(99, 3);
      expect(ouch.landing, 98);
      expect(ouch.bounced, isTrue);
      expect(ouch.via, SnakesLaddersVia.snake);
      expect(ouch.to, 78);
    });

    test('100 must be hit exactly, by steps or by ladder', () {
      expect(SnakesLaddersLogic.move(94, 6).to, 100);
      expect(SnakesLaddersLogic.move(94, 6).bounced, isFalse);
      final ladder = SnakesLaddersLogic.move(77, 3);
      expect(ladder.landing, 80);
      expect(ladder.to, 100);
    });

    test('ladder and snake chains are followed to the end', () {
      expect(
        SnakesLaddersLogic.resolveJumps(
          5,
          ladders: {5: 20, 20: 40},
          snakes: {},
        ),
        (5, 40),
      );
      final m = SnakesLaddersLogic.move(
        2,
        3,
        ladders: {5: 20},
        snakes: {20: 3},
      );
      expect(m.to, 3);
      expect(m.viaFrom, 5);
      expect(m.via, SnakesLaddersVia.snake, reason: 'ended lower');
      // A loop can't hang the game.
      final (_, end) = SnakesLaddersLogic.resolveJumps(
        5,
        ladders: {5: 20},
        snakes: {20: 5},
      );
      expect([5, 20], contains(end));
      expect(SnakesLaddersLogic.resolveJumps(7), (null, 7));
    });

    test('a roll moves, records it and passes the turn', () {
      final c = SnakesLaddersLogic.applyRoll(game(), partner, 2);
      expect(c['turn'], me);
      expect(c.containsKey('status'), isFalse);
      final s = stateOf(c);
      expect(s['positions'], {partner: 2, me: 0});
      expect(s['sixes'], 0);
      expect(lastRollOf(c), {
        'by': partner,
        'value': 2,
        'from': 0,
        'to': 2,
        'via': null,
        'viaFrom': null,
        'viaTo': null,
        'bounced': false,
        'forfeit': false,
        'again': false,
      });
    });

    test('a ladder or snake is written into lastRoll', () {
      final c = SnakesLaddersLogic.applyRoll(
        game(positions: {me: 0, partner: 58}),
        partner,
        4,
      );
      expect(stateOf(c)['positions'], {partner: 19, me: 0});
      final r = lastRollOf(c);
      expect(
        [r['via'], r['viaFrom'], r['viaTo'], r['to']],
        ['snake', 62, 19, 19],
      );
      final roll = SnakesLaddersRoll.fromState(stateOf(c))!;
      expect(SnakesLaddersLogic.describe(roll), 'Ssss… snake 🐍 62 → 19');
      expect(roll.move.landing, 62);
    });

    test('a six rolls again; three in a row ends the turn', () {
      var g = game(positions: {me: 0, partner: 10});
      g = applied(g, SnakesLaddersLogic.applyRoll(g, partner, 6));
      expect(g.turn, partner);
      expect(g.state['sixes'], 1);
      // 10 + 6 lands on the snake at 16.
      expect(SnakesLaddersLogic.positionOf(g.state, partner), 6);
      g = applied(g, SnakesLaddersLogic.applyRoll(g, partner, 6));
      expect(g.turn, partner);
      expect(g.state['sixes'], 2);
      final before = SnakesLaddersLogic.positionOf(g.state, partner);
      final c = SnakesLaddersLogic.applyRoll(g, partner, 6);
      expect(c['turn'], me);
      final s = stateOf(c);
      expect(s['sixes'], 0);
      expect(SnakesLaddersLogic.positionOf(s, partner), before);
      final r = lastRollOf(c);
      expect(r['forfeit'], isTrue);
      expect(r['from'], before);
      expect(r['to'], before);
      expect(
        SnakesLaddersLogic.describe(SnakesLaddersRoll.fromState(s)!),
        contains('Three sixes'),
      );
    });

    test('a non-six after a six resets the count and passes', () {
      var g = game(positions: {me: 0, partner: 30});
      g = applied(g, SnakesLaddersLogic.applyRoll(g, partner, 6));
      final c = SnakesLaddersLogic.applyRoll(g, partner, 2);
      expect(c['turn'], me);
      expect(stateOf(c)['sixes'], 0);
    });

    test('reaching 100 wins, even on a six', () {
      final c = SnakesLaddersLogic.applyRoll(
        game(positions: {me: 0, partner: 94}),
        partner,
        6,
      );
      expect(c['status'], 'finished');
      expect(c['winner'], partner);
      expect(c['turn'], isNull);
      expect(lastRollOf(c)['again'], isFalse);
      expect(
        SnakesLaddersLogic.describe(SnakesLaddersRoll.fromState(stateOf(c))!),
        contains('Made it to 100'),
      );
    });

    test('rejects rolls out of turn, after the end, or out of range', () {
      expect(
        () => SnakesLaddersLogic.applyRoll(game(), me, 3),
        throwsA(isA<GameMoveException>()),
      );
      expect(
        () => SnakesLaddersLogic.applyRoll(game(), partner, 7),
        throwsA(isA<GameMoveException>()),
      );
      expect(
        () => SnakesLaddersLogic.applyRoll(
          game(status: GameStatus.finished, turn: null, winner: me),
          partner,
          3,
        ),
        throwsA(isA<GameMoveException>()),
      );
    });

    test('describe reads each kind of roll', () {
      SnakesLaddersRoll r(Map<String, dynamic> m) =>
          SnakesLaddersRoll.fromState({'lastRoll': m})!;
      expect(
        SnakesLaddersLogic.describe(
          r({
            'by': me,
            'value': 3,
            'from': 25,
            'to': 84,
            'via': 'ladder',
            'viaFrom': 28,
            'viaTo': 84,
          }),
        ),
        'Ladder! 🪜 28 → 84',
      );
      expect(
        SnakesLaddersLogic.describe(
          r({'by': me, 'value': 2, 'from': 5, 'to': 7}),
        ),
        'Moved 5 → 7',
      );
      expect(
        SnakesLaddersLogic.describe(
          r({'by': me, 'value': 6, 'from': 5, 'to': 11, 'again': true}),
        ),
        'Six! Roll again 🎉',
      );
      expect(
        SnakesLaddersLogic.describe(
          r({
            'by': me,
            'value': 5,
            'from': 96,
            'to': 99,
            'via': 'bounce',
            'bounced': true,
          }),
        ),
        'Bounced off 100 ↩️',
      );
      expect(SnakesLaddersRoll.fromState({'lastRoll': 'x'}), isNull);
    });

    test('whole games replay with injected dice and always end', () {
      for (var seed = 0; seed < 25; seed++) {
        final dice = DiceRoller(Random(seed));
        var g = game();
        var writes = 0;
        while (g.isActive) {
          final before = g.moveCount;
          g = applied(g, SnakesLaddersLogic.applyRoll(g, g.turn!, dice.roll()));
          expect(g.moveCount, before + 1);
          for (final p in g.players) {
            final pos = SnakesLaddersLogic.positionOf(g.state, p);
            expect(pos, inInclusiveRange(0, 100));
            expect(SnakesLaddersLogic.ladders.containsKey(pos), isFalse);
            expect(SnakesLaddersLogic.snakes.containsKey(pos), isFalse);
          }
          expect(g.state['sixes'] as int, lessThan(3));
          expect(++writes, lessThan(5000));
        }
        expect(g.isFinished, isTrue);
        expect(SnakesLaddersLogic.positionOf(g.state, g.winner!), 100);
      }
    });
  });

  group('SnakesLaddersScreen', () {
    const user = AppUser(uid: me, displayName: 'Asha', coupleId: 'c1');
    late _FakeGameService service;

    Widget app(Game g, {List<int> rolls = const [], ThemeData? theme}) {
      service = _FakeGameService(g);
      return ProviderScope(
        overrides: [
          gameServiceProvider.overrideWithValue(service),
          gameProvider(g.id).overrideWith((ref) => service.stream),
          currentUserProvider.overrideWithBuild((ref, n) => user),
          partnerProvider.overrideWith((ref) => Stream.value(null)),
          partnerNameProvider.overrideWithValue('Ravi'),
          diceRollerProvider.overrideWithValue(DiceRoller(_Dice([...rolls]))),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light(),
          home: const SnakesLaddersScreen(gameId: 'g1'),
        ),
      );
    }

    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('renders the board and both tokens on a small phone', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(app(game(turn: me)));
      await tester.pumpAndSettle();
      expect(find.text('Your turn'), findsOneWidget);
      expect(find.text('Roll to start!'), findsOneWidget);
      expect(find.byKey(const ValueKey('snl-token-u1')), findsOneWidget);
      expect(find.byKey(const ValueKey('snl-token-u2')), findsOneWidget);
      expect(find.byKey(const ValueKey('dice-roll-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rolling writes the roll and the move together', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        app(
          game(turn: me, positions: {me: 25, partner: 3}),
          rolls: [3],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dice-roll-button')));
      await tester.pumpAndSettle();

      expect(service.results, hasLength(1));
      final c = service.results.single;
      expect(c['turn'], partner);
      expect(stateOf(c)['positions'], {me: 84, partner: 3});
      expect(lastRollOf(c)['via'], 'ladder');
      expect(find.text('You rolled 3'), findsOneWidget);
      expect(find.text('Ladder! 🪜 28 → 84'), findsOneWidget);
      expect(find.text('Ravi\'s turn'), findsOneWidget);
      expect(find.byKey(const ValueKey('dice-roll-button')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a double tap rolls only once', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(game(turn: me), rolls: [6, 6]));
      await tester.pumpAndSettle();
      service.hold = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('dice-roll-button')));
      await tester.pump();
      // Locked while the roll is on its way.
      expect(find.byKey(const ValueKey('dice-roll-button')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('dice-roll')));
      await tester.pump();
      expect(service.results, hasLength(1));
      expect(find.text('Sending your move…'), findsOneWidget);

      service.release();
      await tester.pumpAndSettle();
      // A six: my turn again, and I can roll again.
      expect(find.text('On the board! Six! Roll again 🎉'), findsOneWidget);
      expect(find.byKey(const ValueKey('dice-roll-button')), findsOneWidget);
    });

    testWidgets('the partner\'s roll arrives and animates', (tester) async {
      phone(tester);
      final g = game(positions: {me: 10, partner: 55});
      await tester.pumpWidget(app(g));
      await tester.pumpAndSettle();
      expect(find.text('Waiting for Ravi to move…'), findsOneWidget);
      expect(find.byKey(const ValueKey('dice-roll-button')), findsNothing);

      service.push(applied(g, SnakesLaddersLogic.applyRoll(g, partner, 1)));
      await tester.pump();
      final token = find.byKey(const ValueKey('snl-token-u2'));
      final start = tester.getTopLeft(token);
      await tester.pump(const Duration(milliseconds: 700));
      // Still hopping or sliding, not yet at 53.
      await tester.pumpAndSettle();
      final end = tester.getTopLeft(token);
      expect(end, isNot(start));
      expect(find.text('Ravi rolled 1'), findsOneWidget);
      expect(find.text('Ssss… snake 🐍 56 → 53'), findsOneWidget);
      expect(find.text('Your turn'), findsOneWidget);
    });

    testWidgets('a failed roll shows a snack and unlocks', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(game(turn: me), rolls: [2]));
      await tester.pumpAndSettle();
      service.fail = true;
      await tester.tap(find.byKey(const ValueKey('dice-roll-button')));
      await tester.pumpAndSettle();
      expect(find.text('Could not roll. Check your connection.'), findsOne);
      expect(find.byKey(const ValueKey('dice-roll-button')), findsOneWidget);
    });

    testWidgets('a win shows the result and Play again', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        app(
          game(turn: me, positions: {me: 97, partner: 40}, moveCount: 30),
          rolls: [3],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dice-roll-button')));
      await tester.pumpAndSettle();
      expect(service.results.single['winner'], me);
      expect(find.text('You won!'), findsOneWidget);
      expect(find.text('Play again'), findsOneWidget);
      expect(find.text('Made it to 100! 🏆'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('looks right in dark mode', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        app(
          game(
            positions: {me: 62, partner: 62},
            status: GameStatus.finished,
            turn: null,
            winner: partner,
          ),
          theme: AppTheme.dark(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ravi won'), findsOneWidget);
      // Sharing a square: the tokens stand side by side.
      final a = tester.getCenter(find.byKey(const ValueKey('snl-token-u1')));
      final b = tester.getCenter(find.byKey(const ValueKey('snl-token-u2')));
      expect(a, isNot(b));
      expect(tester.takeException(), isNull);
    });
  });
}
