import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/models/game.dart';

/// Tic-tac-toe rules. Pure Dart: the screen only calls these.
///
/// State (in `Game.state`):
/// - `board`: 9 strings, `''`, `'X'` or `'O'`, index = row * 3 + col.
/// - `marks`: `{uid: 'X' | 'O'}`, written on the first move.
/// - `lastMove`: the index of the last mark placed, or -1.
///
/// Who is X: X always moves first, and the first move belongs to
/// [firstTurn] (the invitee, who just accepted). [markFor] derives the mark
/// from that rule until `marks` has been stored, so both phones agree even
/// before the first move.
class TicTacToeLogic {
  const TicTacToeLogic._();

  static const size = 3;
  static const cells = size * size;
  static const x = 'X';
  static const o = 'O';

  /// Every row, column and diagonal that wins.
  static const lines = <List<int>>[
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8],
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8],
    [0, 4, 8],
    [2, 4, 6],
  ];

  static Map<String, dynamic> newState() => {
    'board': List<String>.filled(cells, ''),
    'marks': <String, String>{},
    'lastMove': -1,
  };

  /// The accepter starts, so the inviter isn't left waiting twice.
  static String firstTurn(Game game) => game.invitee;

  /// The board from [state], always 9 cells long.
  static List<String> board(Map<String, dynamic> state) {
    final raw = state['board'];
    final list = raw is List ? raw : const [];
    return List<String>.generate(cells, (i) {
      final v = i < list.length ? list[i] : null;
      return v == x || v == o ? v as String : '';
    });
  }

  static int lastMove(Map<String, dynamic> state) =>
      (state['lastMove'] as num?)?.toInt() ?? -1;

  /// [uid]'s mark: the stored one, else X for whoever moves first.
  static String markFor(Game game, String uid) {
    final marks = game.state['marks'];
    if (marks is Map) {
      final m = marks[uid];
      if (m == x || m == o) return m as String;
    }
    return uid == firstTurn(game) ? x : o;
  }

  /// The three winning cells, or null if nobody has three in a row.
  static List<int>? winningLine(List<String> board) {
    for (final line in lines) {
      final a = board[line[0]];
      if (a.isNotEmpty && a == board[line[1]] && a == board[line[2]]) {
        return line;
      }
    }
    return null;
  }

  static bool isFull(List<String> board) => board.every((c) => c.isNotEmpty);

  /// Whether [cell] can take a mark right now.
  static bool canPlay(List<String> board, int cell) =>
      cell >= 0 &&
      cell < cells &&
      board[cell].isEmpty &&
      winningLine(board) == null;

  /// The changes for [me] marking [cell], computed from the fresh [game]
  /// inside the transaction. Throws [GameMoveException] when illegal.
  static Map<String, dynamic> applyMove(Game game, String me, int cell) {
    if (!game.isActive) {
      throw const GameMoveException('This game has already ended.');
    }
    if (game.turn != me) {
      throw const GameMoveException('It\'s not your turn yet.');
    }
    final next = board(game.state);
    if (!canPlay(next, cell)) {
      throw const GameMoveException('That square is taken.');
    }
    final mark = markFor(game, me);
    final other = game.opponentOf(me);
    next[cell] = mark;
    final state = <String, dynamic>{
      'board': next,
      'marks': {me: mark, other: mark == x ? o : x},
      'lastMove': cell,
    };
    if (winningLine(next) != null) {
      return {
        'state': state,
        'status': GameStatus.finished.id,
        'turn': null,
        'winner': me,
      };
    }
    if (isFull(next)) {
      return {
        'state': state,
        'status': GameStatus.finished.id,
        'turn': null,
        'winner': Game.draw,
      };
    }
    return {'state': state, 'turn': other};
  }
}
