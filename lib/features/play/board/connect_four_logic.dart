import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/models/game.dart';

/// Connect Four rules. Pure Dart: the screen only calls these.
///
/// State (in `Game.state`):
/// - `board`: 42 strings, `''`, `'R'` or `'Y'`, index = row * 7 + col,
///   row 0 at the top, so discs settle at the highest free row index.
/// - `marks`: `{uid: 'R' | 'Y'}`, written on the first move.
/// - `lastMove`: the index of the last disc dropped, or -1.
///
/// Red always drops first, and the first move belongs to [firstTurn] (the
/// invitee, who just accepted); [colorFor] derives colours from that rule
/// until `marks` has been stored.
class ConnectFourLogic {
  const ConnectFourLogic._();

  static const cols = 7;
  static const rows = 6;
  static const cells = cols * rows;
  static const red = 'R';
  static const yellow = 'Y';

  static Map<String, dynamic> newState() => {
    'board': List<String>.filled(cells, ''),
    'marks': <String, String>{},
    'lastMove': -1,
  };

  /// The accepter starts, so the inviter isn't left waiting twice.
  static String firstTurn(Game game) => game.invitee;

  static int index(int row, int col) => row * cols + col;

  /// The board from [state], always 42 cells long.
  static List<String> board(Map<String, dynamic> state) {
    final raw = state['board'];
    final list = raw is List ? raw : const [];
    return List<String>.generate(cells, (i) {
      final v = i < list.length ? list[i] : null;
      return v == red || v == yellow ? v as String : '';
    });
  }

  static int lastMove(Map<String, dynamic> state) =>
      (state['lastMove'] as num?)?.toInt() ?? -1;

  /// [uid]'s colour: the stored one, else red for whoever moves first.
  static String colorFor(Game game, String uid) {
    final marks = game.state['marks'];
    if (marks is Map) {
      final m = marks[uid];
      if (m == red || m == yellow) return m as String;
    }
    return uid == firstTurn(game) ? red : yellow;
  }

  /// The row a disc dropped in [col] lands on, or null if the column is
  /// full (or out of range).
  static int? dropRow(List<String> board, int col) {
    if (col < 0 || col >= cols) return null;
    for (var row = rows - 1; row >= 0; row--) {
      if (board[index(row, col)].isEmpty) return row;
    }
    return null;
  }

  /// Four (or more) connected cells of one colour, or null. Returns the
  /// first run found, as board indices.
  static List<int>? winningCells(List<String> board) {
    const directions = [(0, 1), (1, 0), (1, 1), (1, -1)];
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final c = board[index(row, col)];
        if (c.isEmpty) continue;
        for (final (dr, dc) in directions) {
          final run = <int>[index(row, col)];
          var r = row + dr;
          var k = col + dc;
          while (r >= 0 &&
              r < rows &&
              k >= 0 &&
              k < cols &&
              board[index(r, k)] == c) {
            run.add(index(r, k));
            r += dr;
            k += dc;
          }
          if (run.length >= 4) return run;
        }
      }
    }
    return null;
  }

  static bool isFull(List<String> board) => board.every((c) => c.isNotEmpty);

  /// Whether a disc can go in [col] right now.
  static bool canDrop(List<String> board, int col) =>
      dropRow(board, col) != null && winningCells(board) == null;

  /// The changes for [me] dropping a disc in [col], computed from the
  /// fresh [game] inside the transaction. Throws [GameMoveException] when
  /// illegal.
  static Map<String, dynamic> applyMove(Game game, String me, int col) {
    if (!game.isActive) {
      throw const GameMoveException('This game has already ended.');
    }
    if (game.turn != me) {
      throw const GameMoveException('It\'s not your turn yet.');
    }
    final next = board(game.state);
    if (winningCells(next) != null) {
      throw const GameMoveException('This game has already ended.');
    }
    final row = dropRow(next, col);
    if (row == null) {
      throw const GameMoveException('That column is full.');
    }
    final color = colorFor(game, me);
    final other = game.opponentOf(me);
    final cell = index(row, col);
    next[cell] = color;
    final state = <String, dynamic>{
      'board': next,
      'marks': {me: color, other: color == red ? yellow : red},
      'lastMove': cell,
    };
    if (winningCells(next) != null) {
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
