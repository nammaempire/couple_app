import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/play/models/game.dart';

void main() {
  Game game({
    GameType type = GameType.ticTacToe,
    GameStatus status = GameStatus.active,
    String? turn = 'a',
    String? winner,
  }) => Game(
    id: 'g',
    type: type,
    status: status,
    createdBy: 'a',
    invitee: 'b',
    turn: turn,
    winner: winner,
  );

  group('Game', () {
    test('reads a stored game, tolerating missing fields', () {
      final g = Game.fromMap('g1', {
        'type': 'connectFour',
        'status': 'active',
        'createdBy': 'a',
        'invitee': 'b',
        'turn': 'b',
        'state': {'board': <String>[]},
        'moveCount': 3,
      })!;
      expect(g.type, GameType.connectFour);
      expect(g.isMyTurn('b'), isTrue);
      expect(g.isMyTurn('a'), isFalse);
      expect(g.moveCount, 3);
      expect(g.state['board'], isEmpty);
      expect(g.players, ['a', 'b']);
    });

    test('skips games this version does not know', () {
      expect(
        Game.fromMap('g', {'type': 'poker', 'createdBy': 'a', 'invitee': 'b'}),
        isNull,
      );
      expect(Game.fromMap('g', {'type': 'ticTacToe'}), isNull);
    });

    test('unknown status counts as cancelled', () {
      final g = Game.fromMap('g', {
        'type': 'ticTacToe',
        'status': '???',
        'createdBy': 'a',
        'invitee': 'b',
      })!;
      expect(g.status, GameStatus.cancelled);
      expect(g.isOpen, isFalse);
    });

    test('who needs to act', () {
      final invite = game(status: GameStatus.invited, turn: null);
      expect(invite.needsActionFrom('b'), isTrue, reason: 'invitee accepts');
      expect(invite.needsActionFrom('a'), isFalse);
      expect(game(turn: 'a').needsActionFrom('a'), isTrue);
      expect(game(turn: 'a').needsActionFrom('b'), isFalse);
      expect(
        game(status: GameStatus.finished, turn: null).needsActionFrom('a'),
        isFalse,
      );
    });

    test('opponent', () {
      expect(game().opponentOf('a'), 'b');
      expect(game().opponentOf('b'), 'a');
    });
  });

  group('HeadToHead', () {
    test('counts wins, draws and games played', () {
      final games = [
        game(status: GameStatus.finished, turn: null, winner: 'a'),
        game(status: GameStatus.finished, turn: null, winner: 'a'),
        game(status: GameStatus.finished, turn: null, winner: 'b'),
        game(status: GameStatus.finished, turn: null, winner: Game.draw),
        game(type: GameType.knowMe, status: GameStatus.finished, turn: null),
        game(status: GameStatus.cancelled, turn: null),
        game(),
      ];
      final all = HeadToHead.from(games);
      expect(all.winsFor('a'), 2);
      expect(all.winsFor('b'), 1);
      expect(all.draws, 1);
      expect(all.played, 5, reason: 'cancelled and active games not counted');

      final quiz = HeadToHead.from(games, type: GameType.knowMe);
      expect(quiz.played, 1);
      expect(quiz.winsFor('a'), 0);
    });
  });
}
