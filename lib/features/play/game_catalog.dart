import 'package:flutter/material.dart';

import 'package:couple_app/features/play/board/connect_four_logic.dart';
import 'package:couple_app/features/play/board/connect_four_screen.dart';
import 'package:couple_app/features/play/board/tic_tac_toe_logic.dart';
import 'package:couple_app/features/play/board/tic_tac_toe_screen.dart';
import 'package:couple_app/features/play/know_me/know_me_logic.dart';
import 'package:couple_app/features/play/know_me/know_me_screen.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/truth_or_dare/truth_or_dare_logic.dart';
import 'package:couple_app/features/play/truth_or_dare/truth_or_dare_screen.dart';

/// Connects each [GameType] to its rules and screen.
class GameCatalog {
  const GameCatalog._();

  /// One line for the game picker.
  static String blurb(GameType type) => switch (type) {
    GameType.knowMe => 'Answer questions about yourself; your partner guesses.',
    GameType.truthOrDare => 'Take turns: sweet truths and playful dares.',
    GameType.ticTacToe => 'Three in a row. Quick and classic.',
    GameType.connectFour => 'Drop discs, connect four to win.',
  };

  /// The state a new game starts with. [inviter] starts the invite.
  static Map<String, dynamic> newState(
    GameType type, {
    required String inviter,
    required String invitee,
  }) => switch (type) {
    GameType.knowMe => KnowMeLogic.newState(subject: inviter),
    GameType.truthOrDare => TruthOrDareLogic.newState(),
    GameType.ticTacToe => TicTacToeLogic.newState(),
    GameType.connectFour => ConnectFourLogic.newState(),
  };

  /// Who acts first when the invite is accepted.
  static String firstTurn(Game game) => switch (game.type) {
    GameType.knowMe => KnowMeLogic.firstTurn(game),
    GameType.truthOrDare => TruthOrDareLogic.firstTurn(game),
    GameType.ticTacToe => TicTacToeLogic.firstTurn(game),
    GameType.connectFour => ConnectFourLogic.firstTurn(game),
  };

  /// The screen that plays [game].
  static Widget screenFor(Game game) => switch (game.type) {
    GameType.knowMe => KnowMeScreen(gameId: game.id),
    GameType.truthOrDare => TruthOrDareScreen(gameId: game.id),
    GameType.ticTacToe => TicTacToeScreen(gameId: game.id),
    GameType.connectFour => ConnectFourScreen(gameId: game.id),
  };

  static Future<void> open(BuildContext context, Game game) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screenFor(game)));
  }
}
