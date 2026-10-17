import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/know_me/know_me_logic.dart';
import 'package:couple_app/features/play/models/game.dart';

/// The quiz's secret answers at
/// `couples/{coupleId}/games/{gameId}/secret/answers`.
///
/// The subject's answers are written there, never into the game, so the
/// guesser can't peek. The rules let the guesser read them only once their
/// guesses are locked in.
class KnowMeService {
  KnowMeService({this._firestore});

  final FirebaseFirestore? _firestore;

  // Resolved lazily so test fakes can subclass without Firebase.
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _gameRef(
    String coupleId,
    String gameId,
  ) => _db.collection('couples').doc(coupleId).collection('games').doc(gameId);

  DocumentReference<Map<String, dynamic>> _secretRef(
    String coupleId,
    String gameId,
  ) => _gameRef(coupleId, gameId).collection('secret').doc('answers');

  /// The subject submits [answers] and hands the turn to the guesser.
  ///
  /// One transaction creates the secret doc and updates the game. The
  /// rules check the secret against the game as it was before this write
  /// (turn and subject are still [me]), so both land together.
  Future<void> submitAnswers({
    required String coupleId,
    required String gameId,
    required String me,
    required List<int> answers,
  }) {
    final gameRef = _gameRef(coupleId, gameId);
    final secretRef = _secretRef(coupleId, gameId);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(gameRef);
      final game = snap.exists ? Game.fromDoc(snap) : null;
      if (game == null) {
        throw const GameMoveException('This game is no longer available.');
      }
      final changes = KnowMeLogic.submitAnswers(game, me, answers);
      tx.set(secretRef, {'subject': me, 'answers': answers});
      tx.update(gameRef, {
        ...changes,
        'moveCount': game.moveCount + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// The subject's answers. Readable by the guesser once their guesses are
  /// locked in.
  Future<List<int>> readAnswers({
    required String coupleId,
    required String gameId,
  }) async {
    final snap = await _secretRef(coupleId, gameId).get();
    final answers = KnowMeLogic.parseAnswers(snap.data()?['answers']);
    if (!snap.exists || answers.isEmpty) {
      throw const GameMoveException('The answers aren\'t available yet.');
    }
    return answers;
  }
}
