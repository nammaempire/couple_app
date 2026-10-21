import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/play/board/board_players_bar.dart';
import 'package:couple_app/features/play/board/board_turn_hint.dart';
import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/dice/dice_roll_bar.dart';
import 'package:couple_app/features/play/dice/dice_roller.dart';
import 'package:couple_app/features/play/ludo/ludo_board.dart';
import 'package:couple_app/features/play/ludo/ludo_logic.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/providers/play_providers.dart';
import 'package:couple_app/features/play/widgets/game_scaffold.dart';

/// Plays one game of Ludo for two.
class LudoScreen extends StatelessWidget {
  const LudoScreen({super.key, required this.gameId});

  final String gameId;

  /// How long a forced move (only one token can go) waits before it is
  /// made for you, so you see the roll first.
  static const autoMoveDelay = Duration(milliseconds: 900);

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      gameId: gameId,
      builder: (context, game, myUid) => _LudoBody(game: game, myUid: myUid),
    );
  }
}

class _LudoBody extends ConsumerStatefulWidget {
  const _LudoBody({required this.game, required this.myUid});

  final Game game;
  final String myUid;

  @override
  ConsumerState<_LudoBody> createState() => _LudoBodyState();
}

class _LudoBodyState extends ConsumerState<_LudoBody> {
  late final GameService _service;
  late final String _coupleId;

  /// The `moveCount` my last write was sent against. Input stays locked
  /// until a newer snapshot arrives, so a double tap can't act twice.
  int? _sentAt;

  /// The `moveCount` of the latest roll write, so the die tumbles once
  /// per roll and not again when the token moves.
  int? _rollId;

  Timer? _autoMove;
  int? _autoMoveAt;

  bool get _busy => _sentAt != null && widget.game.moveCount <= _sentAt!;

  @override
  void initState() {
    super.initState();
    _service = ref.read(gameServiceProvider);
    _coupleId = ref.read(currentCoupleIdProvider);
    if (LudoRoll.fromState(widget.game.state) != null) {
      _rollId = widget.game.moveCount;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoMove());
  }

  @override
  void didUpdateWidget(_LudoBody old) {
    super.didUpdateWidget(old);
    final game = widget.game;
    if (game.moveCount != old.game.moveCount) {
      final roll = LudoRoll.fromState(game.state);
      if (roll != null && !roll.moved) _rollId = game.moveCount;
      _maybeAutoMove();
    }
  }

  @override
  void dispose() {
    _autoMove?.cancel();
    super.dispose();
  }

  /// When only one token can move, move it after a beat. It's still its
  /// own write, like a tap.
  void _maybeAutoMove() {
    if (!mounted) return;
    final game = widget.game;
    final pending = LudoPendingRoll.fromState(game.state);
    if (!game.isMyTurn(widget.myUid) ||
        pending == null ||
        pending.movable.length != 1 ||
        _autoMoveAt == game.moveCount) {
      return;
    }
    _autoMoveAt = game.moveCount;
    _autoMove?.cancel();
    final token = pending.movable.single;
    final at = game.moveCount;
    _autoMove = Timer(LudoScreen.autoMoveDelay, () {
      if (mounted && widget.game.moveCount == at) _moveToken(token);
    });
  }

  Future<void> _send(
    Map<String, dynamic> Function(Game fresh) apply,
    String failure,
  ) async {
    final game = widget.game;
    final me = widget.myUid;
    if (_busy || !game.isMyTurn(me)) return;
    final seen = game.moveCount;
    setState(() => _sentAt = seen);
    try {
      await _service.takeTurn(
        coupleId: _coupleId,
        gameId: game.id,
        me: me,
        apply: (fresh) {
          if (fresh.moveCount != seen) {
            throw const GameMoveException('The game moved on. Try again.');
          }
          return apply(fresh);
        },
      );
    } on GameMoveException catch (e) {
      if (mounted) {
        setState(() => _sentAt = null);
        context.showSnackMessage(e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _sentAt = null);
        context.showSnackMessage(failure);
      }
    }
  }

  void _roll() {
    if (_busy) return;
    final me = widget.myUid;
    final value = ref.read(diceRollerProvider).roll();
    _send(
      (fresh) => LudoLogic.applyRoll(fresh, me, value),
      'Could not roll. Check your connection.',
    );
  }

  void _moveToken(int token) {
    if (_busy) return;
    final me = widget.myUid;
    _autoMove?.cancel();
    HapticFeedback.selectionClick();
    _send(
      (fresh) => LudoLogic.applyMove(fresh, me, token),
      'Could not make that move. Check your connection.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final me = widget.myUid;
    final partner = game.opponentOf(me);
    final partnerName = ref.watch(partnerNameProvider);
    final roll = LudoRoll.fromState(game.state);
    final pending = LudoPendingRoll.fromState(game.state);
    final mode = LudoLogic.modeOf(game.state);
    final myTurn = game.isMyTurn(me);
    final choosing = myTurn && pending != null;
    final mySeat = LudoLogic.seatOf(game, me);
    final partnerSeat = LudoLogic.seatOf(game, partner);
    final myColor = LudoBoard.seatColors[mySeat];
    final myTokens = LudoLogic.tokensOf(game.state, me);
    final home = myTokens.where((t) => t == LudoLogic.home).length;

    Widget pawn(int seat) => Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: LudoBoard.seatColors[seat],
        border: Border.all(color: Colors.white, width: 2),
      ),
    );

    final String title;
    final String? detail;
    if (roll == null) {
      title = myTurn ? 'Roll to start!' : 'No rolls yet';
      detail = '${mode.label}: ${mode.description}';
    } else {
      final who = roll.by == me ? 'You' : partnerName;
      title = '$who rolled ${roll.value}';
      detail =
          LudoLogic.describe(roll) ??
          (roll.by == me
              ? (pending?.movable.length == 1
                    ? 'Moving your only token…'
                    : 'Tap a glowing token to move it.')
              : '$partnerName is picking a token…');
    }

    return Column(
      children: [
        BoardPlayersBar(
          game: game,
          myUid: me,
          partnerName: partnerName,
          myToken: pawn(mySeat),
          partnerToken: pawn(partnerSeat),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: LudoBoard(
                sides: [
                  LudoSide(
                    uid: partner,
                    seat: partnerSeat,
                    tokens: [...LudoLogic.tokensOf(game.state, partner)],
                  ),
                  LudoSide(uid: me, seat: mySeat, tokens: myTokens),
                ],
                myUid: me,
                movable: choosing ? pending.movable : const [],
                onTapToken: choosing && !_busy ? _moveToken : null,
                lastRoll: roll,
                moveKey: game.moveCount,
              ),
            ),
          ),
        ),
        DiceRollBar(
          value: roll?.value,
          rollId: _rollId,
          rolling: _busy && pending == null,
          title: title,
          detail: detail,
          accent: myColor,
          onRoll: myTurn && pending == null && !_busy ? _roll : null,
        ),
        BoardTurnHint(
          game: game,
          myUid: me,
          partnerName: partnerName,
          busy: _busy,
          yourTurnText: choosing
              ? 'Pick a token to move ${pending.value}.'
              : home > 0
              ? '$home of ${myTokens.length} home. Roll the die!'
              : 'Roll the die!',
        ),
      ],
    );
  }
}
