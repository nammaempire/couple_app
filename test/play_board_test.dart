import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/play/board/connect_four_logic.dart';
import 'package:couple_app/features/play/board/connect_four_screen.dart';
import 'package:couple_app/features/play/board/tic_tac_toe_logic.dart';
import 'package:couple_app/features/play/board/tic_tac_toe_screen.dart';
import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/providers/play_providers.dart';

const me = 'u1';
const partner = 'u2';

/// u1 invited u2; u2 accepted, so u2 moves first.
Game game(
  GameType type,
  Map<String, dynamic> state, {
  String? turn = partner,
  GameStatus status = GameStatus.active,
  String? winner,
  int moveCount = 1,
}) => Game(
  id: 'g1',
  type: type,
  status: status,
  createdBy: me,
  invitee: partner,
  turn: turn,
  state: state,
  winner: winner,
  moveCount: moveCount,
);

Map<String, dynamic> ttt(String rows, {int lastMove = -1}) => {
  'board': [for (final c in rows.split('')) c == '.' ? '' : c],
  'marks': <String, String>{},
  'lastMove': lastMove,
};

/// [rows]: 6 strings of 7 chars, top row first; '.' empty.
Map<String, dynamic> c4(List<String> rows) => {
  'board': [
    for (final r in rows)
      for (final c in r.split('')) c == '.' ? '' : c,
  ],
  'marks': <String, String>{},
  'lastMove': -1,
};

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

/// Records takeTurn calls and runs `apply` against the game it was given.
class _FakeGameService implements GameService {
  _FakeGameService(this.current);

  Game current;
  final calls = <String>[];
  final results = <Map<String, dynamic>>[];
  bool fail = false;

  @override
  Future<void> takeTurn({
    required String coupleId,
    required String gameId,
    required String me,
    required Map<String, dynamic> Function(Game game) apply,
  }) async {
    calls.add('takeTurn $coupleId $gameId $me');
    if (fail) throw Exception('offline');
    results.add(apply(current));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  group('TicTacToeLogic', () {
    test('new state is an empty 3x3 board', () {
      final s = TicTacToeLogic.newState();
      expect(s['board'], List.filled(9, ''));
      expect(s['marks'], isEmpty);
      expect(s['lastMove'], -1);
    });

    test('the invitee moves first and is X', () {
      final g = game(GameType.ticTacToe, TicTacToeLogic.newState());
      expect(TicTacToeLogic.firstTurn(g), partner);
      expect(TicTacToeLogic.markFor(g, partner), 'X');
      expect(TicTacToeLogic.markFor(g, me), 'O');
    });

    test('stored marks win over the derived ones', () {
      final g = game(GameType.ticTacToe, {
        ...TicTacToeLogic.newState(),
        'marks': {me: 'X', partner: 'O'},
      });
      expect(TicTacToeLogic.markFor(g, me), 'X');
    });

    test('board() pads and cleans bad data', () {
      expect(TicTacToeLogic.board({}), List.filled(9, ''));
      expect(
        TicTacToeLogic.board({
          'board': ['X', 'Q', 3],
        }),
        ['X', ...List.filled(8, '')],
      );
    });

    test('finds every winning line', () {
      for (final line in TicTacToeLogic.lines) {
        final b = List.filled(9, '');
        for (final i in line) {
          b[i] = 'O';
        }
        expect(TicTacToeLogic.winningLine(b), line);
      }
      expect(TicTacToeLogic.winningLine(List.filled(9, '')), isNull);
      expect(TicTacToeLogic.winningLine('XOXXOOOXX'.split('')), isNull);
    });

    test('a move passes the turn and records marks', () {
      final g = game(GameType.ticTacToe, TicTacToeLogic.newState());
      final c = TicTacToeLogic.applyMove(g, partner, 4);
      expect(c['turn'], me);
      expect(c.containsKey('status'), isFalse);
      final s = c['state'] as Map<String, dynamic>;
      expect((s['board'] as List)[4], 'X');
      expect(s['marks'], {partner: 'X', me: 'O'});
      expect(s['lastMove'], 4);
    });

    test('three in a row finishes with a winner', () {
      // X: 0, 1 · O: 3, 4 · X to play 2.
      final g = game(GameType.ticTacToe, ttt('XX.OO....'));
      final c = TicTacToeLogic.applyMove(g, partner, 2);
      expect(c['status'], 'finished');
      expect(c['turn'], isNull);
      expect(c['winner'], partner);
    });

    test('a full board without a line is a draw', () {
      // X O X / X O O / O X . → X plays 8: no line.
      final g = game(GameType.ticTacToe, ttt('XOXXOOOX.'));
      final c = TicTacToeLogic.applyMove(g, partner, 8);
      expect(c['status'], 'finished');
      expect(c['winner'], Game.draw);
      expect(c['turn'], isNull);
    });

    test('rejects taken squares, out of range, wrong turn, ended games', () {
      final g = game(GameType.ticTacToe, ttt('X........'));
      expect(
        () => TicTacToeLogic.applyMove(g, partner, 0),
        throwsA(isA<GameMoveException>()),
      );
      expect(
        () => TicTacToeLogic.applyMove(g, partner, 9),
        throwsA(isA<GameMoveException>()),
      );
      expect(
        () => TicTacToeLogic.applyMove(g, me, 1),
        throwsA(isA<GameMoveException>()),
      );
      final done = game(
        GameType.ticTacToe,
        ttt('XXX.OO...'),
        status: GameStatus.finished,
        turn: null,
        winner: partner,
      );
      expect(
        () => TicTacToeLogic.applyMove(done, partner, 3),
        throwsA(isA<GameMoveException>()),
      );
    });

    test('a whole game alternates turns and marks', () {
      var g = game(GameType.ticTacToe, TicTacToeLogic.newState());
      // X (partner) wins down the left column.
      for (final cell in [0, 1, 3, 4, 6]) {
        g = applied(g, TicTacToeLogic.applyMove(g, g.turn!, cell));
      }
      expect(g.isFinished, isTrue);
      expect(g.winner, partner);
      expect(TicTacToeLogic.board(g.state).join(), 'XOXOX');
      expect(TicTacToeLogic.markFor(g, me), 'O');
    });
  });

  group('ConnectFourLogic', () {
    const empty = [
      '.......',
      '.......',
      '.......',
      '.......',
      '.......',
      '.......',
    ];

    test('new state is an empty 7x6 board', () {
      final s = ConnectFourLogic.newState();
      expect((s['board'] as List).length, 42);
      expect(s['lastMove'], -1);
      final g = game(GameType.connectFour, s);
      expect(ConnectFourLogic.firstTurn(g), partner);
      expect(ConnectFourLogic.colorFor(g, partner), 'R');
      expect(ConnectFourLogic.colorFor(g, me), 'Y');
    });

    test('discs fall to the lowest free row', () {
      final b = ConnectFourLogic.board(c4(empty));
      expect(ConnectFourLogic.dropRow(b, 3), 5);
      final stacked = ConnectFourLogic.board(
        c4(['.......', '.......', '.......', '.......', '...Y...', '...R...']),
      );
      expect(ConnectFourLogic.dropRow(stacked, 3), 3);
      expect(ConnectFourLogic.dropRow(stacked, -1), isNull);
      expect(ConnectFourLogic.dropRow(stacked, 7), isNull);
    });

    test('a full column is rejected', () {
      final g = game(
        GameType.connectFour,
        c4(['R......', 'Y......', 'R......', 'Y......', 'R......', 'Y......']),
      );
      expect(
        ConnectFourLogic.dropRow(ConnectFourLogic.board(g.state), 0),
        null,
      );
      expect(
        () => ConnectFourLogic.applyMove(g, partner, 0),
        throwsA(isA<GameMoveException>()),
      );
    });

    test('detects horizontal, vertical and both diagonals', () {
      List<int>? win(List<String> rows) =>
          ConnectFourLogic.winningCells(ConnectFourLogic.board(c4(rows)));

      expect(
        win(['.......', '.......', '.......', '.......', '.......', '..RRRR.']),
        [37, 38, 39, 40],
      );
      expect(
        win(['.......', '.......', '......Y', '......Y', '......Y', '......Y']),
        [20, 27, 34, 41],
      );
      // Down-right: (2,0) (3,1) (4,2) (5,3).
      expect(
        win(['.......', '.......', 'R......', 'YR.....', 'YYR....', 'YYYR...']),
        [14, 22, 30, 38],
      );
      // Down-left: (2,6) (3,5) (4,4) (5,3).
      expect(
        win(['.......', '.......', '......Y', '.....YR', '....YRR', '...YRRR']),
        [20, 26, 32, 38],
      );
      expect(
        win(['.......', '.......', '.......', '.......', '.......', 'RRRYRRR']),
        isNull,
      );
      expect(win(empty), isNull);
    });

    test('a move drops, records marks and passes the turn', () {
      final g = game(GameType.connectFour, ConnectFourLogic.newState());
      final c = ConnectFourLogic.applyMove(g, partner, 3);
      expect(c['turn'], me);
      final s = c['state'] as Map<String, dynamic>;
      expect((s['board'] as List)[38], 'R');
      expect(s['lastMove'], 38);
      expect(s['marks'], {partner: 'R', me: 'Y'});
    });

    test('connecting four finishes the game', () {
      final g = game(
        GameType.connectFour,
        c4(['.......', '.......', '.......', '.......', 'YYY....', 'RRR....']),
      );
      final c = ConnectFourLogic.applyMove(g, partner, 3);
      expect(c['status'], 'finished');
      expect(c['winner'], partner);
      expect(c['turn'], isNull);
    });

    test('filling the board without four is a draw', () {
      // Columns alternate in pairs so no four line up anywhere.
      final rows = [
        'RRYYRR.',
        'YYRRYYR',
        'RRYYRRY',
        'YYRRYYR',
        'RRYYRRY',
        'YYRRYYR',
      ];
      final g = game(GameType.connectFour, c4(rows));
      final board = ConnectFourLogic.board(g.state);
      expect(ConnectFourLogic.winningCells(board), isNull);
      final c = ConnectFourLogic.applyMove(g, partner, 6);
      expect(c['status'], 'finished');
      expect(c['winner'], Game.draw);
    });

    test('rejects moves out of turn or after the end', () {
      final g = game(GameType.connectFour, ConnectFourLogic.newState());
      expect(
        () => ConnectFourLogic.applyMove(g, me, 0),
        throwsA(isA<GameMoveException>()),
      );
      expect(
        () => ConnectFourLogic.applyMove(g, partner, 9),
        throwsA(isA<GameMoveException>()),
      );
      final done = game(
        GameType.connectFour,
        ConnectFourLogic.newState(),
        status: GameStatus.finished,
        turn: null,
        winner: Game.draw,
      );
      expect(
        () => ConnectFourLogic.applyMove(done, partner, 0),
        throwsA(isA<GameMoveException>()),
      );
    });
  });

  group('board screens', () {
    const user = AppUser(uid: me, displayName: 'Asha', coupleId: 'c1');

    Widget app(Game g, _FakeGameService service, Widget screen) =>
        ProviderScope(
          overrides: [
            gameServiceProvider.overrideWithValue(service),
            gameProvider(g.id).overrideWith((ref) => Stream.value(g)),
            currentUserProvider.overrideWithBuild((ref, n) => user),
            partnerNameProvider.overrideWithValue('Ravi'),
          ],
          child: MaterialApp(home: screen),
        );

    testWidgets('tic-tac-toe: tapping a square takes a turn', (tester) async {
      final g = game(GameType.ticTacToe, ttt('X........'), turn: me);
      final service = _FakeGameService(g);
      await tester.pumpWidget(
        app(g, service, const TicTacToeScreen(gameId: 'g1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your turn'), findsOneWidget);
      expect(find.text('Tap a square to place your O.'), findsOneWidget);

      // Taken squares do nothing.
      await tester.tap(find.byKey(const ValueKey('ttt-cell-0')));
      await tester.pump();
      expect(service.calls, isEmpty);

      await tester.tap(find.byKey(const ValueKey('ttt-cell-4')));
      await tester.pumpAndSettle();
      expect(service.calls, ['takeTurn c1 g1 u1']);
      final s = service.results.single['state'] as Map<String, dynamic>;
      expect((s['board'] as List)[4], 'O');
      expect(service.results.single['turn'], partner);
    });

    testWidgets('tic-tac-toe: waits calmly on the partner', (tester) async {
      final g = game(GameType.ticTacToe, ttt('.........'));
      final service = _FakeGameService(g);
      await tester.pumpWidget(
        app(g, service, const TicTacToeScreen(gameId: 'g1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ravi\'s turn'), findsOneWidget);
      expect(find.text('Waiting for Ravi to move…'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ttt-cell-4')));
      await tester.pump();
      expect(service.calls, isEmpty);
    });

    testWidgets('tic-tac-toe: a failed move shows a snack', (tester) async {
      final g = game(GameType.ticTacToe, ttt('.........'), turn: me);
      final service = _FakeGameService(g)..fail = true;
      await tester.pumpWidget(
        app(g, service, const TicTacToeScreen(gameId: 'g1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ttt-cell-2')));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not make that move. Check your connection.'),
        findsOneWidget,
      );
    });

    testWidgets('tic-tac-toe: a finished game shows the result', (
      tester,
    ) async {
      final g = game(
        GameType.ticTacToe,
        ttt('OOO.XX.X.'),
        status: GameStatus.finished,
        turn: null,
        winner: me,
        moveCount: 6,
      );
      final service = _FakeGameService(g);
      await tester.pumpWidget(
        app(g, service, const TicTacToeScreen(gameId: 'g1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('You won!'), findsOneWidget);
      expect(find.text('Play again'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ttt-cell-3')));
      await tester.pump();
      expect(service.calls, isEmpty);
    });

    testWidgets('connect four: tapping a column drops a disc', (tester) async {
      final g = game(GameType.connectFour, ConnectFourLogic.newState());
      final service = _FakeGameService(g);
      // u2 (partner) moves first; view the game as u2.
      final widget = ProviderScope(
        overrides: [
          gameServiceProvider.overrideWithValue(service),
          gameProvider('g1').overrideWith((ref) => Stream.value(g)),
          currentUserProvider.overrideWithBuild(
            (ref, n) => const AppUser(
              uid: partner,
              displayName: 'Ravi',
              coupleId: 'c1',
            ),
          ),
          partnerNameProvider.overrideWithValue('Asha'),
        ],
        child: const MaterialApp(home: ConnectFourScreen(gameId: 'g1')),
      );
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();
      expect(find.text('Tap a column to drop your disc.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('c4-col-5')));
      await tester.pumpAndSettle();
      expect(service.calls, ['takeTurn c1 g1 u2']);
      final s = service.results.single['state'] as Map<String, dynamic>;
      expect(s['lastMove'], ConnectFourLogic.index(5, 5));
      expect((s['board'] as List)[ConnectFourLogic.index(5, 5)], 'R');
    });

    testWidgets('connect four: fits a 360 wide phone', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final g = game(
        GameType.connectFour,
        c4(['.......', '.......', '.......', '.......', 'YYY....', 'RRRR...']),
        status: GameStatus.finished,
        turn: null,
        winner: partner,
      );
      final service = _FakeGameService(g);
      await tester.pumpWidget(
        app(g, service, const ConnectFourScreen(gameId: 'g1')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Ravi won'), findsOneWidget);
    });
  });
}
