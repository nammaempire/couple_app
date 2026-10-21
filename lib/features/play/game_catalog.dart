import 'package:flutter/material.dart';

import 'package:couple_app/features/play/board/connect_four_logic.dart';
import 'package:couple_app/features/play/board/connect_four_screen.dart';
import 'package:couple_app/features/play/board/tic_tac_toe_logic.dart';
import 'package:couple_app/features/play/board/tic_tac_toe_screen.dart';
import 'package:couple_app/features/play/know_me/know_me_logic.dart';
import 'package:couple_app/features/play/know_me/know_me_screen.dart';
import 'package:couple_app/features/play/ludo/ludo_logic.dart';
import 'package:couple_app/features/play/ludo/ludo_mode_sheet.dart';
import 'package:couple_app/features/play/ludo/ludo_screen.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/snakes_ladders/snakes_ladders_logic.dart';
import 'package:couple_app/features/play/snakes_ladders/snakes_ladders_screen.dart';
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
    GameType.ludo => 'Race your tokens home. Capture to send them back!',
    GameType.snakesLadders => 'Climb ladders, dodge snakes, first to 100.',
  };

  /// The game's accent colour, for its start card.
  static Color accent(GameType type) => switch (type) {
    GameType.knowMe => const Color(0xFF9B6AD8),
    GameType.truthOrDare => const Color(0xFFE05C7B),
    GameType.ticTacToe => const Color(0xFF4F8FE0),
    GameType.connectFour => const Color(0xFFF5B83D),
    GameType.ludo => const Color(0xFFE5484D),
    GameType.snakesLadders => const Color(0xFF5FAE57),
  };

  /// Asks for anything a game needs settled before the invite goes out
  /// (Ludo's mode). Returns the options for [newState], or null when the
  /// person backed out.
  static Future<Map<String, dynamic>?> pickOptions(
    BuildContext context,
    GameType type,
  ) async {
    if (type != GameType.ludo) return const {};
    final mode = await showLudoModeSheet(context);
    return mode == null ? null : {'mode': mode.id};
  }

  /// The options [game] was played with, so "Play again" keeps them.
  static Map<String, dynamic> optionsOf(Game game) => switch (game.type) {
    GameType.ludo => {'mode': LudoLogic.modeOf(game.state).id},
    _ => const {},
  };

  /// A line about how this particular game is set up, for the invite.
  static String? setupLine(Game game) {
    if (game.type != GameType.ludo) return null;
    final mode = LudoLogic.modeOf(game.state);
    return '${mode.label} game: ${mode.description}';
  }

  /// The state a new game starts with. [inviter] starts the invite;
  /// [options] come from [pickOptions] or [optionsOf].
  static Map<String, dynamic> newState(
    GameType type, {
    required String inviter,
    required String invitee,
    Map<String, dynamic> options = const {},
  }) => switch (type) {
    GameType.knowMe => KnowMeLogic.newState(subject: inviter),
    GameType.truthOrDare => TruthOrDareLogic.newState(),
    GameType.ticTacToe => TicTacToeLogic.newState(),
    GameType.connectFour => ConnectFourLogic.newState(),
    GameType.ludo => LudoLogic.newState(
      inviter: inviter,
      invitee: invitee,
      mode: LudoMode.fromId(options['mode']),
    ),
    GameType.snakesLadders => SnakesLaddersLogic.newState(
      inviter: inviter,
      invitee: invitee,
    ),
  };

  /// Who acts first when the invite is accepted.
  static String firstTurn(Game game) => switch (game.type) {
    GameType.knowMe => KnowMeLogic.firstTurn(game),
    GameType.truthOrDare => TruthOrDareLogic.firstTurn(game),
    GameType.ticTacToe => TicTacToeLogic.firstTurn(game),
    GameType.connectFour => ConnectFourLogic.firstTurn(game),
    GameType.ludo => LudoLogic.firstTurn(game),
    GameType.snakesLadders => SnakesLaddersLogic.firstTurn(game),
  };

  /// The screen that plays [game].
  static Widget screenFor(Game game) => switch (game.type) {
    GameType.knowMe => KnowMeScreen(gameId: game.id),
    GameType.truthOrDare => TruthOrDareScreen(gameId: game.id),
    GameType.ticTacToe => TicTacToeScreen(gameId: game.id),
    GameType.connectFour => ConnectFourScreen(gameId: game.id),
    GameType.ludo => LudoScreen(gameId: game.id),
    GameType.snakesLadders => SnakesLaddersScreen(gameId: game.id),
  };

  static Future<void> open(BuildContext context, Game game) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screenFor(game)));
  }
}
