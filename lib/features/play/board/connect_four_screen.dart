import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/play/board/board_players_bar.dart';
import 'package:couple_app/features/play/board/board_turn_hint.dart';
import 'package:couple_app/features/play/board/connect_four_board.dart';
import 'package:couple_app/features/play/board/connect_four_disc.dart';
import 'package:couple_app/features/play/board/connect_four_logic.dart';
import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/providers/play_providers.dart';
import 'package:couple_app/features/play/widgets/game_scaffold.dart';

/// Plays one game of Connect Four.
class ConnectFourScreen extends StatelessWidget {
  const ConnectFourScreen({super.key, required this.gameId});

  final String gameId;

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      gameId: gameId,
      builder: (context, game, myUid) =>
          _ConnectFourBody(game: game, myUid: myUid),
    );
  }
}

class _ConnectFourBody extends ConsumerStatefulWidget {
  const _ConnectFourBody({required this.game, required this.myUid});

  final Game game;
  final String myUid;

  @override
  ConsumerState<_ConnectFourBody> createState() => _ConnectFourBodyState();
}

class _ConnectFourBodyState extends ConsumerState<_ConnectFourBody> {
  late final GameService _service;
  late final String _coupleId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service = ref.read(gameServiceProvider);
    _coupleId = ref.read(currentCoupleIdProvider);
  }

  Future<void> _drop(int col) async {
    final game = widget.game;
    final me = widget.myUid;
    if (_busy || !game.isMyTurn(me)) return;
    if (!ConnectFourLogic.canDrop(ConnectFourLogic.board(game.state), col)) {
      context.showSnackMessage('That column is full.');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      await _service.takeTurn(
        coupleId: _coupleId,
        gameId: game.id,
        me: me,
        apply: (fresh) => ConnectFourLogic.applyMove(fresh, me, col),
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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final me = widget.myUid;
    final partnerName = ref.watch(partnerNameProvider);
    final board = ConnectFourLogic.board(game.state);
    final myColor = ConnectFourLogic.colorFor(game, me);
    final partnerColor = ConnectFourLogic.colorFor(game, game.opponentOf(me));

    Widget token(String color) =>
        SizedBox.square(dimension: 18, child: ConnectFourDisc(color: color));

    return Column(
      children: [
        BoardPlayersBar(
          game: game,
          myUid: me,
          partnerName: partnerName,
          myToken: token(myColor),
          partnerToken: token(partnerColor),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ConnectFourBoard(
                  board: board,
                  lastMove: ConnectFourLogic.lastMove(game.state),
                  moveCount: game.moveCount,
                  winningCells: ConnectFourLogic.winningCells(board),
                  onDrop: game.isMyTurn(me) && !_busy ? _drop : null,
                ),
              ),
            ),
          ),
        ),
        BoardTurnHint(
          game: game,
          myUid: me,
          partnerName: partnerName,
          busy: _busy,
          yourTurnText: 'Tap a column to drop your disc.',
        ),
      ],
    );
  }
}
