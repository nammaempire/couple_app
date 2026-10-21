import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/avatar/widgets/profile_avatar.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/play/board/board_players_bar.dart';
import 'package:couple_app/features/play/board/board_turn_hint.dart';
import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/dice/dice_roll_bar.dart';
import 'package:couple_app/features/play/dice/dice_roller.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/providers/play_providers.dart';
import 'package:couple_app/features/play/snakes_ladders/snakes_ladders_board.dart';
import 'package:couple_app/features/play/snakes_ladders/snakes_ladders_logic.dart';
import 'package:couple_app/features/play/widgets/game_scaffold.dart';

/// Plays one game of Snakes & Ladders.
class SnakesLaddersScreen extends StatelessWidget {
  const SnakesLaddersScreen({super.key, required this.gameId});

  final String gameId;

  /// Token rings: the inviter's and the invitee's.
  static const inviterColor = Color(0xFFE05C7B);
  static const inviteeColor = Color(0xFF4F8FE0);

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      gameId: gameId,
      builder: (context, game, myUid) =>
          _SnakesLaddersBody(game: game, myUid: myUid),
    );
  }
}

class _SnakesLaddersBody extends ConsumerStatefulWidget {
  const _SnakesLaddersBody({required this.game, required this.myUid});

  final Game game;
  final String myUid;

  @override
  ConsumerState<_SnakesLaddersBody> createState() => _SnakesLaddersBodyState();
}

class _SnakesLaddersBodyState extends ConsumerState<_SnakesLaddersBody> {
  late final GameService _service;
  late final String _coupleId;

  /// The `moveCount` my roll was sent against. Rolling stays locked until
  /// a newer snapshot arrives, so a double tap can't roll twice.
  int? _sentAt;

  bool get _busy => _sentAt != null && widget.game.moveCount <= _sentAt!;

  @override
  void initState() {
    super.initState();
    _service = ref.read(gameServiceProvider);
    _coupleId = ref.read(currentCoupleIdProvider);
  }

  Future<void> _roll() async {
    final game = widget.game;
    final me = widget.myUid;
    if (_busy || !game.isMyTurn(me)) return;
    final seen = game.moveCount;
    final value = ref.read(diceRollerProvider).roll();
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
          return SnakesLaddersLogic.applyRoll(fresh, me, value);
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
        context.showSnackMessage('Could not roll. Check your connection.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final me = widget.myUid;
    final partner = game.opponentOf(me);
    final partnerName = ref.watch(partnerNameProvider);
    final myUser = ref.watch(currentUserProvider);
    final partnerUser = ref.watch(partnerProvider).value;
    final roll = SnakesLaddersRoll.fromState(game.state);
    final canRoll = game.isMyTurn(me) && !_busy;

    Color colorOf(String uid) => uid == game.createdBy
        ? SnakesLaddersScreen.inviterColor
        : SnakesLaddersScreen.inviteeColor;

    Widget face(AppUser? user, String name, double size) =>
        ProfileAvatar(user: user, size: size, fallbackName: name);

    Widget chip(String uid, AppUser? user, String name) => Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colorOf(uid), width: 2),
      ),
      child: ClipOval(child: face(user, name, 18)),
    );

    final String title;
    final String? detail;
    if (roll == null) {
      title = game.isMyTurn(me) ? 'Roll to start!' : 'No rolls yet';
      detail = 'Any roll gets you on the board.';
    } else {
      final who = roll.by == me ? 'You' : partnerName;
      title = '$who rolled ${roll.value}';
      detail = SnakesLaddersLogic.describe(roll);
    }
    final myPos = SnakesLaddersLogic.positionOf(game.state, me);

    return Column(
      children: [
        BoardPlayersBar(
          game: game,
          myUid: me,
          partnerName: partnerName,
          myToken: chip(me, myUser, 'You'),
          partnerToken: chip(partner, partnerUser, partnerName),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SnakesLaddersBoard(
                positions: {
                  me: myPos,
                  partner: SnakesLaddersLogic.positionOf(game.state, partner),
                },
                tokens: [
                  SnakesLaddersToken(
                    uid: game.createdBy,
                    color: colorOf(game.createdBy),
                    face: game.createdBy == me
                        ? face(myUser, myUser.displayName, 40)
                        : face(partnerUser, partnerName, 40),
                  ),
                  SnakesLaddersToken(
                    uid: game.invitee,
                    color: colorOf(game.invitee),
                    face: game.invitee == me
                        ? face(myUser, myUser.displayName, 40)
                        : face(partnerUser, partnerName, 40),
                  ),
                ],
                lastRoll: roll,
                moveKey: game.moveCount,
              ),
            ),
          ),
        ),
        DiceRollBar(
          value: roll?.value,
          rollId: roll == null ? null : game.moveCount,
          rolling: _busy,
          title: title,
          detail: detail,
          accent: colorOf(me),
          onRoll: canRoll ? _roll : null,
        ),
        BoardTurnHint(
          game: game,
          myUid: me,
          partnerName: partnerName,
          busy: _busy,
          yourTurnText: myPos == 0
              ? 'Roll the die to get going.'
              : 'You\'re on $myPos. Roll the die!',
        ),
      ],
    );
  }
}
