import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:couple_app/features/play/models/game.dart';

/// Thrown when a move can't be applied: the game moved on, it isn't your
/// turn, or it is no longer open.
class GameMoveException implements Exception {
  const GameMoveException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Reads and writes `couples/{coupleId}/games`.
///
/// Every change to a game goes through [move], a transaction that checks
/// the game is still in the state the caller saw and bumps `moveCount`, so
/// two phones can never both apply a move.
class GameService {
  GameService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _games(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('games');

  DocumentReference<Map<String, dynamic>> gameRef(
    String coupleId,
    String gameId,
  ) => _games(coupleId).doc(gameId);

  /// The couple's most recent games, newest first.
  Stream<List<Game>> watchGames(String coupleId, {int limit = 100}) {
    return _games(coupleId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(Game.fromDoc).whereType<Game>().toList());
  }

  /// One game, live. Emits null if it disappears or can't be read.
  Stream<Game?> watchGame(String coupleId, String gameId) {
    return gameRef(
      coupleId,
      gameId,
    ).snapshots().map((doc) => doc.exists ? Game.fromDoc(doc) : null);
  }

  /// Invites [invitee] to a new game and returns its id. The game starts
  /// once they accept.
  Future<String> invite({
    required String coupleId,
    required GameType type,
    required String me,
    required String invitee,
    Map<String, dynamic> state = const {},
  }) async {
    final ref = _games(coupleId).doc();
    await ref.set({
      'type': type.id,
      'status': GameStatus.invited.id,
      'createdBy': me,
      'invitee': invitee,
      'players': [me, invitee],
      'turn': null,
      'state': state,
      'winner': null,
      'moveCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'finishedAt': null,
    });
    return ref.id;
  }

  /// Applies one change to a game in a transaction.
  ///
  /// [apply] receives the latest game and returns the fields to change
  /// (`status`, `turn`, `state`, `winner`), or throws [GameMoveException].
  /// `moveCount`, `updatedAt` and, when finishing, `finishedAt` are added
  /// here.
  Future<void> move({
    required String coupleId,
    required String gameId,
    required Map<String, dynamic> Function(Game game) apply,
  }) {
    final ref = gameRef(coupleId, gameId);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final game = snap.exists ? Game.fromDoc(snap) : null;
      if (game == null) {
        throw const GameMoveException('This game is no longer available.');
      }
      final changes = apply(game);
      tx.update(ref, {
        ...changes,
        'moveCount': game.moveCount + 1,
        'updatedAt': FieldValue.serverTimestamp(),
        if (changes['status'] == GameStatus.finished.id)
          'finishedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// The invited partner accepts; [firstTurn] decides who acts first and
  /// [state] may replace the starting state (e.g. dealt questions).
  Future<void> accept({
    required String coupleId,
    required String gameId,
    required String me,
    required String firstTurn,
    Map<String, dynamic>? state,
  }) {
    return move(
      coupleId: coupleId,
      gameId: gameId,
      apply: (game) {
        if (!game.isInvite || game.invitee != me) {
          throw const GameMoveException('This invite is no longer open.');
        }
        return {
          'status': GameStatus.active.id,
          'turn': firstTurn,
          'state': ?state,
        };
      },
    );
  }

  /// Declines an invite, withdraws one, or leaves an active game. Either
  /// player may do this at any time while the game is open.
  Future<void> cancel({required String coupleId, required String gameId}) {
    return move(
      coupleId: coupleId,
      gameId: gameId,
      apply: (game) {
        if (!game.isOpen) {
          throw const GameMoveException('This game has already ended.');
        }
        return {'status': GameStatus.cancelled.id, 'turn': null};
      },
    );
  }

  /// Applies a turn: only allowed when the game is active and it is [me]'s
  /// turn. [apply] returns the changed fields (usually `state`, `turn`,
  /// and when the game ends `status: finished` and `winner`).
  Future<void> takeTurn({
    required String coupleId,
    required String gameId,
    required String me,
    required Map<String, dynamic> Function(Game game) apply,
  }) {
    return move(
      coupleId: coupleId,
      gameId: gameId,
      apply: (game) {
        if (!game.isActive) {
          throw const GameMoveException('This game has already ended.');
        }
        if (game.turn != me) {
          throw const GameMoveException('It\'s not your turn yet.');
        }
        return apply(game);
      },
    );
  }
}
