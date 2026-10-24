import 'package:couple_app/core/backend/backend.dart';
import 'package:flutter/material.dart';

/// The games two partners can play together.
enum GameType {
  knowMe(
    'knowMe',
    'How well do you know me?',
    '🧠',
    Icons.psychology_alt_outlined,
  ),
  truthOrDare('truthOrDare', 'Truth or Dare', '🎲', Icons.casino_outlined),
  ticTacToe('ticTacToe', 'Tic-tac-toe', '⭕', Icons.grid_3x3),
  connectFour('connectFour', 'Connect Four', '🔴', Icons.view_column_outlined),
  ludo('ludo', 'Ludo', '🏠', Icons.grid_view_rounded),
  snakesLadders(
    'snakesLadders',
    'Snakes & Ladders',
    '🐍',
    Icons.stairs_outlined,
  );

  const GameType(this.id, this.label, this.emoji, this.icon);
  final String id;
  final String label;
  final String emoji;
  final IconData icon;

  /// Null for an unknown id, so old app versions skip games they can't play.
  static GameType? fromId(String? id) {
    for (final t in values) {
      if (t.id == id) return t;
    }
    return null;
  }
}

enum GameStatus {
  /// Waiting for the invited partner to accept.
  invited('invited'),
  active('active'),
  finished('finished'),

  /// Declined, withdrawn, or abandoned before it finished.
  cancelled('cancelled');

  const GameStatus(this.id);
  final String id;

  static GameStatus fromId(String? id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return GameStatus.cancelled;
  }
}

/// One game session, stored at `couples/{coupleId}/games/{id}`.
///
/// Every game uses the same envelope. [turn] always names the person who
/// must act next (move, answer, guess, judge), and the security rules only
/// let that person change an active game. [moveCount] goes up by exactly
/// one with every write, so two phones can never both apply a move.
/// Game-specific data lives in [state].
class Game {
  const Game({
    required this.id,
    required this.type,
    required this.status,
    required this.createdBy,
    required this.invitee,
    this.turn,
    this.state = const {},
    this.winner,
    this.moveCount = 0,
    this.createdAt,
    this.updatedAt,
    this.finishedAt,
  });

  final String id;
  final GameType type;
  final GameStatus status;

  /// Who started the game (and the invite).
  final String createdBy;

  /// The partner who was invited.
  final String invitee;

  /// Whose action the game is waiting for; null when not active.
  final String? turn;

  /// Game-specific data: a board, quiz questions, the current card…
  final Map<String, dynamic> state;

  /// The winner's uid, [draw], or null when there is no winner (yet).
  final String? winner;
  final int moveCount;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? finishedAt;

  static const draw = 'draw';

  List<String> get players => [createdBy, invitee];

  bool get isInvite => status == GameStatus.invited;
  bool get isActive => status == GameStatus.active;
  bool get isFinished => status == GameStatus.finished;
  bool get isOpen => isInvite || isActive;
  bool get isDraw => winner == draw;

  bool isMyTurn(String uid) => isActive && turn == uid;

  /// The other player.
  String opponentOf(String uid) => uid == createdBy ? invitee : createdBy;

  /// Whether [uid] has something to do: accept an invite or take a turn.
  bool needsActionFrom(String uid) =>
      (isInvite && invitee == uid) || isMyTurn(uid);

  static Game? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      fromMap(doc.id, doc.data() ?? const {});

  /// Null when the document is not a game this app version understands.
  static Game? fromMap(String id, Map<String, dynamic> data) {
    final type = GameType.fromId(data['type'] as String?);
    final createdBy = data['createdBy'];
    final invitee = data['invitee'];
    if (type == null || createdBy is! String || invitee is! String) {
      return null;
    }
    final state = data['state'];
    return Game(
      id: id,
      type: type,
      status: GameStatus.fromId(data['status'] as String?),
      createdBy: createdBy,
      invitee: invitee,
      turn: data['turn'] as String?,
      state: state is Map ? Map<String, dynamic>.from(state) : const {},
      winner: data['winner'] as String?,
      moveCount: (data['moveCount'] as num?)?.toInt() ?? 0,
      createdAt: _date(data['createdAt']),
      updatedAt: _date(data['updatedAt']),
      finishedAt: _date(data['finishedAt']),
    );
  }

  static DateTime? _date(Object? v) => switch (v) {
    final Timestamp t => t.toDate(),
    final DateTime d => d,
    _ => null,
  };
}

/// Wins for each player across finished games, for the head-to-head card.
class HeadToHead {
  const HeadToHead({this.wins = const {}, this.draws = 0, this.played = 0});

  final Map<String, int> wins;
  final int draws;
  final int played;

  int winsFor(String uid) => wins[uid] ?? 0;

  /// Tallies finished games, optionally only of [type]. Games without a
  /// winner (quizzes, truth or dare) count as played but not won.
  static HeadToHead from(Iterable<Game> games, {GameType? type}) {
    final wins = <String, int>{};
    var draws = 0;
    var played = 0;
    for (final g in games) {
      if (!g.isFinished || (type != null && g.type != type)) continue;
      played++;
      final w = g.winner;
      if (w == null) continue;
      if (w == Game.draw) {
        draws++;
      } else {
        wins[w] = (wins[w] ?? 0) + 1;
      }
    }
    return HeadToHead(wins: wins, draws: draws, played: played);
  }
}
