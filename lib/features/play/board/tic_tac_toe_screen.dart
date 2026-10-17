import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/play/board/board_players_bar.dart';
import 'package:couple_app/features/play/board/board_turn_hint.dart';
import 'package:couple_app/features/play/board/tic_tac_toe_board.dart';
import 'package:couple_app/features/play/board/tic_tac_toe_logic.dart';
import 'package:couple_app/features/play/board/tic_tac_toe_mark.dart';
import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/providers/play_providers.dart';
import 'package:couple_app/features/play/widgets/game_scaffold.dart';

/// Plays one game of tic-tac-toe.
class TicTacToeScreen extends StatelessWidget {
  const TicTacToeScreen({super.key, required this.gameId});

  final String gameId;

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      gameId: gameId,
      builder: (context, game, myUid) =>
          _TicTacToeBody(game: game, myUid: myUid),
    );
  }
}

class _TicTacToeBody extends ConsumerStatefulWidget {
  const _TicTacToeBody({required this.game, required this.myUid});

  final Game game;
  final String myUid;

  @override
  ConsumerState<_TicTacToeBody> createState() => _TicTacToeBodyState();
}

class _TicTacToeBodyState extends ConsumerState<_TicTacToeBody> {
  late final GameService _service;
  late final String _coupleId;

  /// The square being sent, while a move is in flight.
  int? _pending;

  @override
  void initState() {
    super.initState();
    _service = ref.read(gameServiceProvider);
    _coupleId = ref.read(currentCoupleIdProvider);
  }

  Future<void> _play(int cell) async {
    final game = widget.game;
    final me = widget.myUid;
    if (_pending != null || !game.isMyTurn(me)) return;
    if (!TicTacToeLogic.canPlay(TicTacToeLogic.board(game.state), cell)) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _pending = cell);
    try {
      await _service.takeTurn(
        coupleId: _coupleId,
        gameId: game.id,
        me: me,
        apply: (fresh) => TicTacToeLogic.applyMove(fresh, me, cell),
      );
    } on GameMoveException catch (e) {
      if (mounted) context.showSnackMessage(e.message);
    } catch (_) {
      if (mounted) {
        context.showSnackMessage(
          'Could not make that move. Check your connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final me = widget.myUid;
    final partnerName = ref.watch(partnerNameProvider);
    final board = TicTacToeLogic.board(game.state);
    final myMark = TicTacToeLogic.markFor(game, me);
    final partnerMark = TicTacToeLogic.markFor(game, game.opponentOf(me));
    final canTap = game.isMyTurn(me) && _pending == null;
    // A move may already be on the board by the time the call returns.
    final pending = _pending != null && board[_pending!].isEmpty
        ? _pending
        : null;

    return Column(
      children: [
        BoardPlayersBar(
          game: game,
          myUid: me,
          partnerName: partnerName,
          myToken: TicTacToeMark(mark: myMark),
          partnerToken: TicTacToeMark(mark: partnerMark),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: TicTacToeBoard(
                  board: board,
                  lastMove: TicTacToeLogic.lastMove(game.state),
                  winningLine: TicTacToeLogic.winningLine(board),
                  pendingCell: pending,
                  pendingMark: myMark,
                  onTap: canTap ? _play : null,
                ),
              ),
            ),
          ),
        ),
        BoardTurnHint(
          game: game,
          myUid: me,
          partnerName: partnerName,
          busy: _pending != null,
          yourTurnText: 'Tap a square to place your $myMark.',
        ),
      ],
    );
  }
}
