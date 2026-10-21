import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/core/theme/app_theme.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/dice/dice_roller.dart';
import 'package:couple_app/features/play/game_catalog.dart';
import 'package:couple_app/features/play/ludo/ludo_geometry.dart';
import 'package:couple_app/features/play/ludo/ludo_logic.dart';
import 'package:couple_app/features/play/ludo/ludo_screen.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/providers/play_providers.dart';
import 'package:couple_app/features/play/screens/play_hub_screen.dart';

const me = 'u1';
const partner = 'u2';
const y = LudoLogic.yard;
const h = LudoLogic.home;

/// u1 (red) invited u2 (yellow); u2 accepted, so u2 rolls first.
Game game({
  List<int> mine = const [y, y, y, y],
  List<int> theirs = const [y, y, y, y],
  LudoMode mode = LudoMode.classic,
  Map<String, dynamic>? pendingRoll,
  Map<String, dynamic>? lastRoll,
  int sixes = 0,
  String? turn = me,
  GameStatus status = GameStatus.active,
  String? winner,
  int moveCount = 1,
}) => Game(
  id: 'g1',
  type: GameType.ludo,
  status: status,
  createdBy: me,
  invitee: partner,
  turn: turn,
  state: {
    'mode': mode.id,
    'tokens': {me: mine, partner: theirs},
    'pendingRoll': pendingRoll,
    'lastRoll': lastRoll,
    'sixes': sixes,
  },
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

List<int> tokensOf(Map<String, dynamic> changes, String uid) =>
    LudoLogic.tokensOf(stateOf(changes), uid);

/// Rolls [value] then moves [token] (or the only movable one).
Game turn(Game g, int value, [int? token]) {
  final who = g.turn!;
  g = applied(g, LudoLogic.applyRoll(g, who, value));
  final pending = LudoPendingRoll.fromState(g.state);
  if (pending == null) return g;
  return applied(
    g,
    LudoLogic.applyMove(g, who, token ?? pending.movable.single),
  );
}

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
  final invites = <Map<String, dynamic>>[];

  /// Holds writes until [release], to test double taps.
  Completer<void>? hold;

  Stream<Game?> get stream => _controller.stream;

  void release() => hold?.complete();

  @override
  Future<void> takeTurn({
    required String coupleId,
    required String gameId,
    required String me,
    required Map<String, dynamic> Function(Game game) apply,
  }) async {
    final changes = apply(current);
    results.add(changes);
    await hold?.future;
    current = applied(current, changes);
    _controller.add(current);
  }

  @override
  Future<String> invite({
    required String coupleId,
    required GameType type,
    required String me,
    required String invitee,
    Map<String, dynamic> state = const {},
  }) async {
    invites.add(state);
    return 'new1';
  }

  @override
  Stream<Game?> watchGame(String coupleId, String gameId) => Stream.value(
    Game(
      id: gameId,
      type: GameType.ludo,
      status: GameStatus.invited,
      createdBy: me,
      invitee: partner,
      state: invites.isEmpty ? const {} : invites.last,
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  group('LudoLogic', () {
    test('new games: classic has 4 tokens, quick 2, all in the yard', () {
      final classic = LudoLogic.newState(inviter: me, invitee: partner);
      expect(classic, {
        'mode': 'classic',
        'tokens': {
          me: [y, y, y, y],
          partner: [y, y, y, y],
        },
        'pendingRoll': null,
        'lastRoll': null,
        'sixes': 0,
      });
      final quick = GameCatalog.newState(
        GameType.ludo,
        inviter: me,
        invitee: partner,
        options: {'mode': 'quick'},
      );
      expect(quick['mode'], 'quick');
      expect((quick['tokens'] as Map)[me], [y, y]);
      expect(LudoLogic.firstTurn(game()), partner);
    });

    test('Play again keeps the mode', () {
      final g = game(mode: LudoMode.quick, mine: [y, y], theirs: [y, y]);
      expect(GameCatalog.optionsOf(g), {'mode': 'quick'});
      expect(GameCatalog.setupLine(g), startsWith('Quick game'));
      expect(LudoMode.fromId('nonsense'), LudoMode.classic);
    });

    test('the inviter is red and the invitee yellow, opposite', () {
      final g = game();
      expect(LudoLogic.seatOf(g, me), LudoLogic.red);
      expect(LudoLogic.seatOf(g, partner), LudoLogic.yellow);
      expect(LudoLogic.absolute(0, LudoLogic.red), 0);
      expect(LudoLogic.absolute(0, LudoLogic.yellow), 26);
      expect(LudoLogic.absolute(50, LudoLogic.red), 50);
      expect(LudoLogic.absolute(50, LudoLogic.yellow), 24);
      expect(LudoLogic.absolute(y, LudoLogic.red), isNull);
      expect(LudoLogic.absolute(51, LudoLogic.red), isNull);
      expect(LudoLogic.absolute(h, LudoLogic.yellow), isNull);
    });

    test('tokensOf pads and cleans bad data', () {
      expect(LudoLogic.tokensOf({}, me), [y, y, y, y]);
      expect(
        LudoLogic.tokensOf({
          'mode': 'quick',
          'tokens': {
            me: [3, 'x', 9],
          },
        }, me),
        [3, y],
      );
      expect(
        LudoLogic.tokensOf({
          'tokens': {
            me: [99, -7],
          },
        }, me),
        [h, y, y, y],
      );
    });

    test('the board geometry is consistent', () {
      expect(LudoGeometry.track.length, LudoLogic.trackLength);
      expect(LudoGeometry.track.toSet().length, LudoLogic.trackLength);
      // Every step on the track is to a neighbouring square; the four
      // inner corners are crossed diagonally, as on a real board.
      var diagonals = 0;
      for (var i = 0; i < LudoGeometry.track.length; i++) {
        final a = LudoGeometry.track[i];
        final b = LudoGeometry.track[(i + 1) % LudoGeometry.track.length];
        final dx = (a.$1 - b.$1).abs();
        final dy = (a.$2 - b.$2).abs();
        expect(max(dx, dy), 1, reason: '$i');
        if (dx + dy == 2) diagonals++;
      }
      expect(diagonals, 4);
      for (var seat = 0; seat < 4; seat++) {
        final column = LudoGeometry.homeColumns[seat];
        expect(column.length, LudoLogic.lastColumn - LudoLogic.firstColumn + 1);
        // The column starts beside the seat's last track square.
        final last = LudoGeometry.track[LudoLogic.absolute(50, seat)!];
        final first = column.first;
        expect((last.$1 - first.$1).abs() + (last.$2 - first.$2).abs(), 1);
      }
      expect(LudoGeometry.path(LudoLogic.red, 0, y, 0), hasLength(2));
      expect(LudoGeometry.path(LudoLogic.red, 0, 48, 53), hasLength(6));
    });

    test('a token needs a 6 to leave the yard (1 or 6 in Quick)', () {
      for (var v = 1; v <= 5; v++) {
        expect(LudoLogic.destination(y, v, LudoMode.classic), isNull);
      }
      expect(LudoLogic.destination(y, 6, LudoMode.classic), 0);
      expect(LudoLogic.destination(y, 1, LudoMode.quick), 0);
      expect(LudoLogic.destination(y, 6, LudoMode.quick), 0);
      expect(LudoLogic.destination(y, 3, LudoMode.quick), isNull);
    });

    test('reaching home needs an exact roll', () {
      expect(LudoLogic.destination(48, 5, LudoMode.classic), 53);
      expect(LudoLogic.destination(53, 3, LudoMode.classic), h);
      expect(LudoLogic.destination(53, 4, LudoMode.classic), isNull);
      expect(LudoLogic.destination(55, 1, LudoMode.classic), h);
      expect(LudoLogic.destination(55, 2, LudoMode.classic), isNull);
      expect(LudoLogic.destination(h, 1, LudoMode.classic), isNull);
      expect(LudoLogic.legalMoves([y, 10, 53, h], 3, LudoMode.classic), [1, 2]);
      expect(LudoLogic.legalMoves([y, 10, 53, h], 4, LudoMode.classic), [1]);
    });

    test('landing on an opponent captures it, except on safe squares', () {
      // Yellow progress 31 sits on track square 5.
      expect(
        LudoLogic.captures(
          progress: 5,
          seat: LudoLogic.red,
          opponent: [31, 2, y, h],
          opponentSeat: LudoLogic.yellow,
        ),
        [0],
      );
      // Square 8 is a star.
      expect(LudoLogic.isSafe(8), isTrue);
      expect(
        LudoLogic.captures(
          progress: 8,
          seat: LudoLogic.red,
          opponent: [34],
          opponentSeat: LudoLogic.yellow,
        ),
        isEmpty,
      );
      // Yellow's start square (26) is safe too.
      expect(
        LudoLogic.captures(
          progress: 26,
          seat: LudoLogic.red,
          opponent: [0, 0],
          opponentSeat: LudoLogic.yellow,
        ),
        isEmpty,
      );
      // Home columns are private.
      expect(
        LudoLogic.captures(
          progress: 52,
          seat: LudoLogic.red,
          opponent: [52, 26],
          opponentSeat: LudoLogic.yellow,
        ),
        isEmpty,
      );
      // Two opponent tokens on the square both go.
      expect(
        LudoLogic.captures(
          progress: 5,
          seat: LudoLogic.red,
          opponent: [31, 31],
          opponentSeat: LudoLogic.yellow,
        ),
        [0, 1],
      );
    });

    test('rolling with no legal move passes the turn at once', () {
      final c = LudoLogic.applyRoll(game(), me, 3);
      expect(c['turn'], partner);
      final s = stateOf(c);
      expect(s['pendingRoll'], isNull);
      expect(s['sixes'], 0);
      expect(lastRollOf(c), {
        'by': me,
        'value': 3,
        'token': null,
        'from': null,
        'to': null,
        'captured': <int>[],
        'passed': true,
        'forfeit': false,
        'again': false,
      });
      expect(LudoLogic.describe(LudoRoll.fromState(s)!), 'No moves this time.');
    });

    test('a roll with moves keeps the turn and waits for a token', () {
      final c = LudoLogic.applyRoll(game(mine: [y, 10, 53, h]), me, 3);
      expect(c['turn'], me);
      final s = stateOf(c);
      expect(s['pendingRoll'], {
        'value': 3,
        'movable': [1, 2],
      });
      expect(lastRollOf(c)['passed'], isFalse);
      expect(LudoLogic.describe(LudoRoll.fromState(s)!), isNull);
      // You can't roll again before moving.
      expect(
        () => LudoLogic.applyRoll(applied(game(), c), me, 4),
        throwsA(isA<GameMoveException>()),
      );
    });

    test('leaving the yard on a 6, then rolling again', () {
      var g = applied(game(), LudoLogic.applyRoll(game(), me, 6));
      expect(g.state['sixes'], 1);
      expect(LudoPendingRoll.fromState(g.state)!.movable, [0, 1, 2, 3]);
      final c = LudoLogic.applyMove(g, me, 2);
      expect(c['turn'], me, reason: 'a six rolls again');
      expect(tokensOf(c, me), [y, y, 0, y]);
      expect(stateOf(c)['pendingRoll'], isNull);
      expect(stateOf(c)['sixes'], 1);
      expect(lastRollOf(c), {
        'by': me,
        'value': 6,
        'token': 2,
        'from': y,
        'to': 0,
        'captured': <int>[],
        'passed': false,
        'forfeit': false,
        'again': true,
      });
      g = applied(g, c);
      expect(
        LudoLogic.describe(LudoRoll.fromState(g.state)!),
        contains('yard'),
      );
    });

    test('an ordinary move passes the turn', () {
      final g = turn(game(mine: [10, y, y, y]), 4);
      expect(g.turn, partner);
      expect(LudoLogic.tokensOf(g.state, me), [14, y, y, y]);
      expect(g.state['sixes'], 0);
    });

    test('a capture sends the token home and earns another roll', () {
      final g = turn(game(mine: [3, y, y, y], theirs: [31, 40, y, y]), 2);
      expect(LudoLogic.tokensOf(g.state, partner), [y, 40, y, y]);
      expect(LudoLogic.tokensOf(g.state, me), [5, y, y, y]);
      expect(g.turn, me);
      final r = LudoRoll.fromState(g.state)!;
      expect(r.captured, [0]);
      expect(r.again, isTrue);
      expect(g.state['sixes'], 0);
      expect(LudoLogic.describe(r), contains('Captured!'));
    });

    test('no capture on a safe square: both tokens share it', () {
      final g = turn(game(mine: [5, y, y, y], theirs: [34, y, y, y]), 3);
      expect(LudoLogic.tokensOf(g.state, partner), [34, y, y, y]);
      expect(LudoLogic.tokensOf(g.state, me), [8, y, y, y]);
      expect(g.turn, partner);
    });

    test('the opponent can capture me too', () {
      // Red on 10 = square 10; yellow from 34 (square 8) rolls 2.
      var g = game(mine: [10, y, y, y], theirs: [34, y, y, y], turn: partner);
      g = turn(g, 2);
      expect(LudoLogic.tokensOf(g.state, me), [y, y, y, y]);
      expect(LudoLogic.tokensOf(g.state, partner), [36, y, y, y]);
      expect(g.turn, partner);
    });

    test('three sixes in a row forfeit the turn', () {
      var g = game(mine: [10, y, y, y]);
      g = turn(g, 6, 0);
      expect((g.turn, g.state['sixes']), (me, 1));
      g = turn(g, 6, 0);
      expect((g.turn, g.state['sixes']), (me, 2));
      final c = LudoLogic.applyRoll(g, me, 6);
      expect(c['turn'], partner);
      final s = stateOf(c);
      expect(s['sixes'], 0);
      expect(s['pendingRoll'], isNull);
      expect(tokensOf(c, me), [22, y, y, y], reason: 'no move');
      expect(lastRollOf(c)['forfeit'], isTrue);
      expect(LudoLogic.describe(LudoRoll.fromState(s)!), contains('Three'));
    });

    test('a non-six resets the run of sixes', () {
      var g = turn(game(mine: [10, y, y, y]), 6, 0);
      g = turn(g, 6, 0);
      g = turn(g, 2);
      expect(g.turn, partner);
      expect(g.state['sixes'], 0);
    });

    test('moves are checked against the pending roll', () {
      final g = game(mine: [10, y, y, y]);
      expect(
        () => LudoLogic.applyMove(g, me, 0),
        throwsA(isA<GameMoveException>()),
        reason: 'roll first',
      );
      final rolled = applied(g, LudoLogic.applyRoll(g, me, 4));
      expect(
        () => LudoLogic.applyMove(rolled, me, 1),
        throwsA(isA<GameMoveException>()),
        reason: 'token 1 is in the yard',
      );
      expect(
        () => LudoLogic.applyMove(rolled, partner, 0),
        throwsA(isA<GameMoveException>()),
      );
      expect(
        () => LudoLogic.applyRoll(game(turn: partner), me, 3),
        throwsA(isA<GameMoveException>()),
      );
      expect(
        () => LudoLogic.applyRoll(g, me, 0),
        throwsA(isA<GameMoveException>()),
      );
    });

    test('bringing the last token home wins', () {
      final g = turn(game(mine: [53, h, h, h]), 3);
      expect(g.isFinished, isTrue);
      expect(g.winner, me);
      expect(g.turn, isNull);
      final r = LudoRoll.fromState(g.state)!;
      expect(r.to, h);
      expect(r.again, isFalse);
      expect(LudoLogic.describe(r), 'Token home! 🏠');
    });

    test('quick mode: two tokens, out on a 1, two home wins', () {
      var g = game(mode: LudoMode.quick, mine: [y, y], theirs: [y, y]);
      final c = LudoLogic.applyRoll(g, me, 1);
      expect(stateOf(c)['pendingRoll'], {
        'value': 1,
        'movable': [0, 1],
      });
      g = applied(applied(g, c), LudoLogic.applyMove(applied(g, c), me, 0));
      expect(LudoLogic.tokensOf(g.state, me), [0, y]);
      expect(g.turn, partner, reason: 'a 1 does not roll again');
      expect(g.state['mode'], 'quick');

      final win = turn(
        game(mode: LudoMode.quick, mine: [h, 50], theirs: [y, y]),
        6,
      );
      expect(win.winner, me);
    });

    test('whole games replay with injected dice and always end', () {
      for (final mode in LudoMode.values) {
        for (var seed = 0; seed < 12; seed++) {
          final dice = DiceRoller(Random(seed));
          var g = Game(
            id: 'g',
            type: GameType.ludo,
            status: GameStatus.active,
            createdBy: me,
            invitee: partner,
            turn: partner,
            state: LudoLogic.newState(
              inviter: me,
              invitee: partner,
              mode: mode,
            ),
          );
          var writes = 0;
          while (g.isActive) {
            final who = g.turn!;
            final pending = LudoPendingRoll.fromState(g.state);
            final changes = pending == null
                ? LudoLogic.applyRoll(g, who, dice.roll())
                // Prefer the furthest-back token, to exercise captures.
                : LudoLogic.applyMove(g, who, pending.movable.first);
            g = applied(g, changes);
            for (final p in g.players) {
              for (final t in LudoLogic.tokensOf(g.state, p)) {
                expect(t, inInclusiveRange(y, h));
              }
            }
            expect(g.state['sixes'] as int, lessThan(3));
            expect(++writes, lessThan(20000));
          }
          expect(g.isFinished, isTrue);
          expect(
            LudoLogic.allHome(LudoLogic.tokensOf(g.state, g.winner!)),
            isTrue,
          );
        }
      }
    });
  });

  group('LudoScreen', () {
    const user = AppUser(uid: me, displayName: 'Asha', coupleId: 'c1');
    late _FakeGameService service;

    Widget app(Game g, {List<int> rolls = const [], ThemeData? theme}) {
      service = _FakeGameService(g);
      return ProviderScope(
        overrides: [
          gameServiceProvider.overrideWithValue(service),
          gameProvider(g.id).overrideWith((ref) => service.stream),
          currentUserProvider.overrideWithBuild((ref, n) => user),
          partnerNameProvider.overrideWithValue('Ravi'),
          diceRollerProvider.overrideWithValue(DiceRoller(_Dice([...rolls]))),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light(),
          home: const LudoScreen(gameId: 'g1'),
        ),
      );
    }

    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    /// Lets animations run; the movable tokens pulse forever, so
    /// pumpAndSettle would never return.
    Future<void> run(WidgetTester tester, [int ms = 1500]) async {
      for (var t = 0; t < ms; t += 100) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('roll a 6, then tap a token to leave the yard', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(game(), rolls: [6]));
      await run(tester);
      expect(find.text('Your turn'), findsOneWidget);
      expect(find.text('Roll to start!'), findsOneWidget);
      expect(find.byKey(const ValueKey('ludo-token-0')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('dice-roll-button')));
      await run(tester);
      expect(service.results, hasLength(1));
      expect(service.results.single['turn'], me);
      expect(find.text('You rolled 6'), findsOneWidget);
      expect(find.text('Tap a glowing token to move it.'), findsOneWidget);
      expect(find.text('Pick a token to move 6.'), findsOneWidget);
      expect(find.byKey(const ValueKey('dice-roll-button')), findsNothing);

      // A double tap only moves once.
      service.hold = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('ludo-token-2')));
      await tester.pump();
      expect(find.byKey(const ValueKey('ludo-token-2')), findsNothing);
      service.release();
      await run(tester);
      expect(service.results, hasLength(2));
      final move = service.results.last;
      expect(tokensOf(move, me), [y, y, 0, y]);
      expect(move['turn'], me);
      expect(find.text('Out of the yard 🚀 · Roll again 🎉'), findsOneWidget);
      expect(find.byKey(const ValueKey('dice-roll-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with no legal move the turn passes', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(game(), rolls: [3]));
      await run(tester);
      await tester.tap(find.byKey(const ValueKey('dice-roll-button')));
      await run(tester);
      expect(service.results, hasLength(1));
      expect(service.results.single['turn'], partner);
      expect(find.text('No moves this time.'), findsOneWidget);
      expect(find.text('Ravi\'s turn'), findsOneWidget);
    });

    testWidgets('a single movable token moves by itself', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(game(mine: [10, y, y, y]), rolls: [3]));
      await run(tester);
      await tester.tap(find.byKey(const ValueKey('dice-roll-button')));
      await run(tester, 400);
      expect(service.results, hasLength(1));
      expect(find.text('Moving your only token…'), findsOneWidget);
      await run(tester, 1500);
      expect(service.results, hasLength(2));
      expect(tokensOf(service.results.last, me), [13, y, y, y]);
      expect(service.results.last['turn'], partner);
    });

    testWidgets('capturing bursts and sends the token back', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        app(
          game(
            mine: [3, 20, y, y],
            theirs: [31, y, y, y],
            pendingRoll: {
              'value': 2,
              'movable': [0, 1],
            },
            lastRoll: {'by': me, 'value': 2},
          ),
        ),
      );
      await run(tester, 300);
      await tester.tap(find.byKey(const ValueKey('ludo-token-0')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('💥'), findsOneWidget);
      await run(tester);
      expect(find.text('💥'), findsNothing);
      final c = service.results.single;
      expect(tokensOf(c, partner), [y, y, y, y]);
      expect(lastRollOf(c)['captured'], [0]);
      expect(c['turn'], me);
      expect(
        find.text('Moved 2 · Captured! 💥 Back to the yard · Roll again 🎉'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('bringing the last token home shows the win', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        app(
          game(
            mine: [53, h, h, h],
            theirs: [20, 30, y, y],
            pendingRoll: {
              'value': 3,
              'movable': [0],
            },
            lastRoll: {'by': me, 'value': 3},
            moveCount: 40,
          ),
        ),
      );
      await run(tester, 200);
      await tester.tap(find.byKey(const ValueKey('ludo-token-0')));
      await run(tester);
      expect(service.results, hasLength(1), reason: 'no auto-move as well');
      expect(service.results.single['winner'], me);
      expect(find.text('You won!'), findsOneWidget);
      expect(find.text('Play again'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the partner\'s view: waiting, no tokens to tap', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        app(
          game(
            turn: partner,
            mine: [10, y, y, y],
            theirs: [0, y, y, y],
            pendingRoll: {
              'value': 5,
              'movable': [0],
            },
            lastRoll: {'by': partner, 'value': 5},
          ),
        ),
      );
      await run(tester);
      expect(find.text('Ravi rolled 5'), findsOneWidget);
      expect(find.text('Ravi is picking a token…'), findsOneWidget);
      expect(find.byKey(const ValueKey('ludo-token-0')), findsNothing);
      expect(find.byKey(const ValueKey('dice-roll-button')), findsNothing);
      expect(service.results, isEmpty);
    });

    testWidgets('quick mode in dark mode fits a small phone', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        app(
          game(
            mode: LudoMode.quick,
            mine: [h, 12],
            theirs: [h, h],
            status: GameStatus.finished,
            turn: null,
            winner: partner,
          ),
          theme: AppTheme.dark(),
        ),
      );
      await run(tester);
      expect(find.text('Ravi won'), findsOneWidget);
      expect(find.byKey(const ValueKey('ludo-my-token-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('ludo-their-token-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('ludo-my-token-2')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Ludo from the hub', () {
    testWidgets('choosing a mode before the invite', (tester) async {
      tester.view.physicalSize = const Size(390, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = _FakeGameService(game());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gameServiceProvider.overrideWithValue(service),
            gamesProvider.overrideWith((ref) => Stream.value(const <Game>[])),
            currentUserProvider.overrideWithBuild(
              (ref, n) =>
                  const AppUser(uid: me, displayName: 'Asha', coupleId: 'c1'),
            ),
            coupleProvider.overrideWith(
              (ref) => Stream.value(
                const Couple(
                  id: 'c1',
                  inviteCode: 'X',
                  memberIds: [me, partner],
                ),
              ),
            ),
            partnerNameProvider.overrideWithValue('Ravi'),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const PlayHubScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('start-snakesLadders')), findsOneWidget);

      // Backing out of the sheet sends nothing.
      await tester.tap(find.byKey(const ValueKey('start-ludo')));
      await tester.pumpAndSettle();
      expect(find.text('Which Ludo?'), findsOneWidget);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(service.invites, isEmpty);

      await tester.tap(find.byKey(const ValueKey('start-ludo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ludo-mode-quick')));
      await tester.pumpAndSettle();
      expect(service.invites, hasLength(1));
      expect(service.invites.single['mode'], 'quick');
      expect((service.invites.single['tokens'] as Map)[me], [y, y]);
      // The invite screen says which game it is.
      expect(find.text('Waiting for Ravi'), findsOneWidget);
      expect(find.textContaining('Quick game'), findsOneWidget);
    });
  });
}
