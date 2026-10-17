import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/empty_state.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/game_catalog.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/providers/play_providers.dart';

/// Builds the part of a game screen that is specific to one game: the
/// board, the quiz, the card. Called for active and finished games.
typedef GameBodyBuilder =
    Widget Function(BuildContext context, Game game, String myUid);

/// The frame every game screen shares.
///
/// Loads the game, and handles everything that isn't the game itself:
/// accepting or declining an invite, waiting for the partner, the "whose
/// turn" strip, leaving, the result banner and "Play again". [builder]
/// draws the game for active and finished games.
class GameScaffold extends ConsumerWidget {
  const GameScaffold({super.key, required this.gameId, required this.builder});

  final String gameId;
  final GameBodyBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(gameProvider(gameId));
    final myUid = ref.watch(currentUidProvider);
    final partnerName = ref.watch(partnerNameProvider);
    final game = gameState.value;

    if (game == null) {
      return Scaffold(
        appBar: AppBar(),
        body: gameState.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const EmptyState(
                icon: Icons.sports_esports_outlined,
                text: 'This game is no longer available.',
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(game.type.label),
        actions: [
          if (game.isOpen)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (_) => _leave(context, ref, game, partnerName),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'leave',
                  child: Text(game.isInvite ? 'Cancel invite' : 'Leave game'),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: switch (game.status) {
          GameStatus.invited => _InviteBody(
            game: game,
            myUid: myUid,
            partnerName: partnerName,
          ),
          GameStatus.cancelled => const EmptyState(
            icon: Icons.flag_outlined,
            text: 'This game ended early.',
          ),
          GameStatus.active || GameStatus.finished => Column(
            children: [
              GameStatusStrip(
                game: game,
                myUid: myUid,
                partnerName: partnerName,
              ),
              Expanded(child: builder(context, game, myUid)),
              if (game.isFinished) _PlayAgainBar(game: game, myUid: myUid),
            ],
          ),
        },
      ),
    );
  }

  Future<void> _leave(
    BuildContext context,
    WidgetRef ref,
    Game game,
    String partnerName,
  ) async {
    final service = ref.read(gameServiceProvider);
    final coupleId = ref.read(currentCoupleIdProvider);
    final invite = game.isInvite;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(invite ? 'Cancel this invite?' : 'Leave this game?'),
        content: Text(
          invite
              ? '$partnerName won\'t be able to join it.'
              : 'The game ends for both of you and nobody wins.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep playing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(invite ? 'Cancel invite' : 'Leave'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await service.cancel(coupleId: coupleId, gameId: game.id);
    } on GameMoveException catch (e) {
      if (context.mounted) context.showSnackMessage(e.message);
    } catch (_) {
      if (context.mounted) {
        context.showSnackMessage('Could not leave. Check your connection.');
      }
    }
  }
}

/// "Your turn" / "Ravi's turn" / the result, under the app bar.
class GameStatusStrip extends StatelessWidget {
  const GameStatusStrip({
    super.key,
    required this.game,
    required this.myUid,
    required this.partnerName,
  });

  final Game game;
  final String myUid;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (String text, IconData icon, Color bg, Color fg) = switch (game) {
      Game(isFinished: true, isDraw: true) => (
        'It\'s a draw',
        Icons.handshake_outlined,
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      Game(isFinished: true, winner: final w?) when w == myUid => (
        'You won!',
        Icons.emoji_events_outlined,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      Game(isFinished: true, winner: final w?) when w != myUid => (
        '$partnerName won',
        Icons.emoji_events_outlined,
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      Game(isFinished: true) => (
        'Game over',
        Icons.check_circle_outline,
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      _ when game.isMyTurn(myUid) => (
        'Your turn',
        Icons.touch_app_outlined,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      _ => (
        '$partnerName\'s turn',
        Icons.hourglass_top_rounded,
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An invite: the invitee accepts or declines; the inviter waits.
class _InviteBody extends ConsumerStatefulWidget {
  const _InviteBody({
    required this.game,
    required this.myUid,
    required this.partnerName,
  });

  final Game game;
  final String myUid;
  final String partnerName;

  @override
  ConsumerState<_InviteBody> createState() => _InviteBodyState();
}

class _InviteBodyState extends ConsumerState<_InviteBody> {
  late final GameService _service;
  late final String _coupleId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service = ref.read(gameServiceProvider);
    _coupleId = ref.read(currentCoupleIdProvider);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on GameMoveException catch (e) {
      if (mounted) context.showSnackMessage(e.message);
    } catch (_) {
      if (mounted) {
        context.showSnackMessage('Could not reach the game. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final theme = Theme.of(context);
    final invitedMe = game.invitee == widget.myUid;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(game.type.emoji, style: const TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              invitedMe
                  ? '${widget.partnerName} wants to play'
                  : 'Waiting for ${widget.partnerName}',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              invitedMe
                  ? '${game.type.label}. ${GameCatalog.blurb(game.type)}'
                  : 'They\'ll get your invite to ${game.type.label} in the '
                        'Play tab. The game starts when they accept.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            if (invitedMe) ...[
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => _service.accept(
                          coupleId: _coupleId,
                          gameId: game.id,
                          me: widget.myUid,
                          firstTurn: GameCatalog.firstTurn(game),
                        ),
                      ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Let\'s play'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => _service.cancel(
                          coupleId: _coupleId,
                          gameId: game.id,
                        ),
                      ),
                child: const Text('Not now'),
              ),
            ] else
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => _service.cancel(
                          coupleId: _coupleId,
                          gameId: game.id,
                        ),
                      ),
                child: const Text('Cancel invite'),
              ),
          ],
        ),
      ),
    );
  }
}

/// After a game: start the same game again, as a new invite.
class _PlayAgainBar extends ConsumerStatefulWidget {
  const _PlayAgainBar({required this.game, required this.myUid});

  final Game game;
  final String myUid;

  @override
  ConsumerState<_PlayAgainBar> createState() => _PlayAgainBarState();
}

class _PlayAgainBarState extends ConsumerState<_PlayAgainBar> {
  bool _busy = false;

  Future<void> _playAgain() async {
    final service = ref.read(gameServiceProvider);
    final coupleId = ref.read(currentCoupleIdProvider);
    final game = widget.game;
    final partner = game.opponentOf(widget.myUid);
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // If either of you already started the next game, join that one
      // instead of creating a second.
      final existing = (ref.read(gamesProvider).value ?? const <Game>[])
          .where((g) => g.isOpen && g.type == game.type && g.id != game.id)
          .firstOrNull;
      if (existing != null) {
        if (existing.isInvite && existing.invitee == widget.myUid) {
          await service.accept(
            coupleId: coupleId,
            gameId: existing.id,
            me: widget.myUid,
            firstTurn: GameCatalog.firstTurn(existing),
          );
        }
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => GameCatalog.screenFor(existing),
          ),
        );
        return;
      }
      final id = await service.invite(
        coupleId: coupleId,
        type: game.type,
        me: widget.myUid,
        invitee: partner,
        state: GameCatalog.newState(
          game.type,
          inviter: widget.myUid,
          invitee: partner,
        ),
      );
      if (!mounted) return;
      final next = Game(
        id: id,
        type: game.type,
        status: GameStatus.invited,
        createdBy: widget.myUid,
        invitee: partner,
      );
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => GameCatalog.screenFor(next)),
      );
    } catch (_) {
      if (mounted) {
        context.showSnackMessage('Could not start a new game. Try again.');
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Done'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : _playAgain,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Play again'),
            ),
          ),
        ],
      ),
    );
  }
}
