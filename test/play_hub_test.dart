import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/providers/play_providers.dart';
import 'package:couple_app/features/play/screens/play_hub_screen.dart';
import 'package:couple_app/features/play/widgets/play_hub_lists.dart';

const me = 'u1';
const partner = 'u2';
final base = DateTime(2026, 10, 16, 12);

Game g(
  String id,
  GameType type,
  GameStatus status, {
  String createdBy = me,
  String? turn,
  String? winner,
  Map<String, dynamic> state = const {},
  int moveCount = 1,
  int minutesAgo = 0,
}) => Game(
  id: id,
  type: type,
  status: status,
  createdBy: createdBy,
  invitee: createdBy == me ? partner : me,
  turn: turn,
  winner: winner,
  state: state,
  moveCount: moveCount,
  createdAt: base.subtract(Duration(minutes: minutesAgo + 5)),
  updatedAt: base.subtract(Duration(minutes: minutesAgo)),
  finishedAt: status == GameStatus.finished
      ? base.subtract(Duration(minutes: minutesAgo))
      : null,
);

/// Records calls instead of touching Firestore.
class _FakeGameService implements GameService {
  _FakeGameService(this.games);

  final List<Game> games;
  final calls = <String>[];

  @override
  Future<String> invite({
    required String coupleId,
    required GameType type,
    required String me,
    required String invitee,
    Map<String, dynamic> state = const {},
  }) async {
    calls.add('invite $coupleId ${type.id} $me $invitee ${state.keys}');
    return 'new1';
  }

  @override
  Future<void> accept({
    required String coupleId,
    required String gameId,
    required String me,
    required String firstTurn,
    Map<String, dynamic>? state,
  }) async => calls.add('accept $gameId $me $firstTurn');

  @override
  Future<void> cancel({
    required String coupleId,
    required String gameId,
  }) async => calls.add('cancel $gameId');

  @override
  Stream<Game?> watchGame(String coupleId, String gameId) {
    for (final game in games) {
      if (game.id == gameId) return Stream.value(game);
    }
    return Stream.value(
      Game(
        id: gameId,
        type: GameType.ticTacToe,
        status: GameStatus.invited,
        createdBy: me,
        invitee: partner,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  group('PlayHubLists', () {
    final invite = g(
      'a',
      GameType.connectFour,
      GameStatus.invited,
      createdBy: partner,
      minutesAgo: 3,
    );
    final myTurn = g(
      'b',
      GameType.ticTacToe,
      GameStatus.active,
      turn: me,
      minutesAgo: 1,
    );
    final theirTurn = g(
      'c',
      GameType.truthOrDare,
      GameStatus.active,
      turn: partner,
    );
    final myInvite = g('d', GameType.knowMe, GameStatus.invited);
    final won = g(
      'e',
      GameType.ticTacToe,
      GameStatus.finished,
      winner: me,
      minutesAgo: 60,
    );
    final lost = g(
      'f',
      GameType.connectFour,
      GameStatus.finished,
      winner: partner,
      minutesAgo: 30,
    );
    final all = [won, invite, theirTurn, lost, myTurn, myInvite];

    test('splits open games by who has to act, newest first', () {
      expect(PlayHubLists.waitingOnMe(all, me).map((g) => g.id), ['b', 'a']);
      expect(PlayHubLists.waitingOnPartner(all, me).map((g) => g.id), [
        'c',
        'd',
      ]);
      expect(PlayHubLists.waitingOnMe(all, partner).map((g) => g.id), [
        'c',
        'd',
      ]);
    });

    test('recent lists finished and cancelled games, capped', () {
      final ended = g(
        'x',
        GameType.ticTacToe,
        GameStatus.cancelled,
        minutesAgo: 10,
      );
      expect(PlayHubLists.recent([...all, ended]).map((g) => g.id), [
        'x',
        'f',
        'e',
      ]);
      final many = [
        for (var i = 0; i < 15; i++)
          g('$i', GameType.ticTacToe, GameStatus.finished, minutesAgo: i),
      ];
      expect(PlayHubLists.recent(many).length, 10);
      expect(PlayHubLists.recent(many).first.id, '0');
    });

    test('openOf finds an open game of a type', () {
      expect(PlayHubLists.openOf(all, GameType.ticTacToe)?.id, 'b');
      expect(PlayHubLists.openOf([won, lost], GameType.ticTacToe), isNull);
    });

    test('status text reads from my side', () {
      expect(PlayHubLists.statusText(invite, me, 'Ravi'), 'Ravi invited you');
      expect(
        PlayHubLists.statusText(myInvite, me, 'Ravi'),
        'Invite sent to Ravi',
      );
      expect(PlayHubLists.statusText(myTurn, me, 'Ravi'), 'Your turn');
      expect(PlayHubLists.statusText(theirTurn, me, 'Ravi'), 'Ravi\'s turn');
    });

    test('result text covers wins, draws, quizzes and early ends', () {
      expect(PlayHubLists.resultText(won, me, 'Ravi'), 'You won');
      expect(PlayHubLists.resultText(lost, me, 'Ravi'), 'Ravi won');
      expect(
        PlayHubLists.resultText(
          g('d', GameType.ticTacToe, GameStatus.finished, winner: Game.draw),
          me,
          'Ravi',
        ),
        'Draw',
      );
      expect(
        PlayHubLists.resultText(
          g(
            'q',
            GameType.knowMe,
            GameStatus.finished,
            state: {'score': 4, 'total': 5},
          ),
          me,
          'Ravi',
        ),
        'Quiz: 4/5',
      );
      expect(
        PlayHubLists.resultText(
          g('q', GameType.knowMe, GameStatus.finished),
          me,
          'Ravi',
        ),
        'Quiz done',
      );
      expect(
        PlayHubLists.resultText(
          g('t', GameType.truthOrDare, GameStatus.finished),
          me,
          'Ravi',
        ),
        'Played',
      );
      expect(
        PlayHubLists.resultText(
          g('c', GameType.ticTacToe, GameStatus.cancelled, moveCount: 4),
          me,
          'Ravi',
        ),
        'Ended early',
      );
      expect(
        PlayHubLists.resultText(
          g('c', GameType.ticTacToe, GameStatus.cancelled, moveCount: 1),
          me,
          'Ravi',
        ),
        'Not played',
      );
    });

    test('relative time', () {
      final now = DateTime(2026, 10, 16, 12);
      String rel(DateTime t) => PlayHubLists.relativeTime(t, now);
      expect(PlayHubLists.relativeTime(null, now), '');
      expect(rel(now.subtract(const Duration(seconds: 20))), 'just now');
      expect(rel(now.subtract(const Duration(minutes: 5))), '5m ago');
      expect(rel(now.subtract(const Duration(hours: 3))), '3h ago');
      expect(rel(DateTime(2026, 10, 15, 23)), 'Yesterday');
      expect(rel(DateTime(2026, 10, 12, 9)), '4d ago');
      expect(rel(DateTime(2026, 3, 12)), '12 Mar');
      expect(rel(DateTime(2025, 3, 12)), '12 Mar 2025');
    });
  });

  group('PlayHubScreen', () {
    const user = AppUser(uid: me, displayName: 'Asha', coupleId: 'c1');
    const couple = Couple(id: 'c1', inviteCode: 'X', memberIds: [me, partner]);

    Widget app(
      _FakeGameService service, {
      Stream<List<Game>>? games,
      Couple c = couple,
    }) => ProviderScope(
      retry: (retryCount, error) => null,
      overrides: [
        gameServiceProvider.overrideWithValue(service),
        gamesProvider.overrideWith(
          (ref) => games ?? Stream.value(service.games),
        ),
        currentUserProvider.overrideWithBuild((ref, n) => user),
        coupleProvider.overrideWith((ref) => Stream.value(c)),
        partnerNameProvider.overrideWithValue('Ravi'),
      ],
      child: const MaterialApp(home: PlayHubScreen()),
    );

    void tallView(WidgetTester tester) {
      tester.view.physicalSize = const Size(390, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    final games = [
      g(
        'inv',
        GameType.connectFour,
        GameStatus.invited,
        createdBy: partner,
        minutesAgo: 2,
      ),
      g('ttt', GameType.ticTacToe, GameStatus.active, turn: me, minutesAgo: 4),
      g('tod', GameType.truthOrDare, GameStatus.active, turn: partner),
      g(
        'w1',
        GameType.ticTacToe,
        GameStatus.finished,
        winner: me,
        moveCount: 6,
        minutesAgo: 90,
      ),
      g(
        'w2',
        GameType.connectFour,
        GameStatus.finished,
        winner: partner,
        moveCount: 20,
        minutesAgo: 80,
      ),
      g(
        'q',
        GameType.knowMe,
        GameStatus.finished,
        state: {'score': 4, 'total': 5},
        minutesAgo: 70,
      ),
      g(
        'd',
        GameType.ticTacToe,
        GameStatus.finished,
        winner: Game.draw,
        minutesAgo: 60,
      ),
      g('x', GameType.ticTacToe, GameStatus.cancelled, moveCount: 3),
    ];

    testWidgets('renders every section from the games list', (tester) async {
      tallView(tester);
      final service = _FakeGameService(games);
      await tester.pumpWidget(app(service));
      await tester.pumpAndSettle();

      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Waiting on you'), findsOneWidget);
      expect(find.text('Ravi invited you'), findsOneWidget);
      expect(find.text('Your turn'), findsOneWidget);
      expect(find.text('Waiting on Ravi'), findsOneWidget);
      expect(find.text('Ravi\'s turn'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);

      expect(find.text('Start a game'), findsOneWidget);
      for (final type in GameType.values) {
        expect(find.byKey(ValueKey('start-${type.id}')), findsOneWidget);
      }

      expect(find.text('Head to head'), findsOneWidget);
      expect(find.text('4 played · 1 draw'), findsOneWidget);
      expect(find.text('You 1 · Ravi 0 · 1 drawn'), findsOneWidget);
      expect(find.text('You 0 · Ravi 1'), findsOneWidget);

      expect(find.text('Recent games'), findsOneWidget);
      expect(find.text('You won'), findsOneWidget);
      expect(find.text('Ravi won'), findsOneWidget);
      expect(find.text('Quiz: 4/5'), findsOneWidget);
      expect(find.text('Draw'), findsOneWidget);
      expect(find.text('Ended early'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('accepting and declining invites inline', (tester) async {
      tallView(tester);
      final service = _FakeGameService(games);
      await tester.pumpWidget(app(service));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(service.calls, ['cancel inv']);

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      // Connect Four: the accepter (invitee, me) moves first.
      expect(service.calls.last, 'accept inv u1 u1');
    });

    testWidgets('starting a game invites the partner and opens it', (
      tester,
    ) async {
      tallView(tester);
      final service = _FakeGameService([]);
      await tester.pumpWidget(app(service));
      await tester.pumpAndSettle();
      expect(find.textContaining('No games yet'), findsOneWidget);
      expect(find.text('Head to head'), findsNothing);
      expect(find.text('Recent games'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('start-ticTacToe')));
      await tester.pumpAndSettle();
      expect(service.calls, [
        'invite c1 ticTacToe u1 u2 (board, marks, lastMove)',
      ]);
      // The new game's invite screen.
      expect(find.text('Waiting for Ravi'), findsOneWidget);
    });

    testWidgets('an open game of that type is opened, not duplicated', (
      tester,
    ) async {
      tallView(tester);
      final service = _FakeGameService(games);
      await tester.pumpWidget(app(service));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('start-ticTacToe')));
      await tester.pumpAndSettle();
      expect(service.calls, isEmpty);
      expect(find.textContaining('already have a Tic-tac-toe game'), findsOne);
      // The open game's board.
      expect(find.byKey(const ValueKey('ttt-cell-0')), findsOneWidget);
    });

    testWidgets('starting is disabled until the partner joins', (tester) async {
      tallView(tester);
      final service = _FakeGameService([]);
      await tester.pumpWidget(
        app(
          service,
          c: const Couple(id: 'c1', inviteCode: 'X', memberIds: [me]),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('You can start games once Ravi has joined.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('start-ticTacToe')));
      await tester.pumpAndSettle();
      expect(service.calls, isEmpty);
    });

    testWidgets('shows an error when games fail to load', (tester) async {
      final service = _FakeGameService([]);
      await tester.pumpWidget(
        app(service, games: Stream.error(Exception('denied'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not load your games.'), findsOneWidget);
      expect(find.text('Start a game'), findsOneWidget);
    });

    testWidgets('fits a 360 wide phone', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = _FakeGameService(games);
      await tester.pumpWidget(app(service));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
