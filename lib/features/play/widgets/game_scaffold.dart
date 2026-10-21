import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/empty_state.dart';
import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/game_catalog.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/providers/play_providers.dart';
import 'package:couple_app/features/play/widgets/play_look.dart';

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

    final theme = Theme.of(context);
    final preset = PlayLook.page(game, myUid);
    final particles = PlayLook.particles(game, myUid);
    final dark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: preset.colors(theme.brightness).first,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
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
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedGradientBackground(
              preset: preset,
              duration: const Duration(seconds: 14),
            ),
          ),
          if (particles != null)
            Positioned.fill(
              child: FloatingHearts(
                style: particles,
                count: particles == ParticleStyle.confetti ? 18 : 12,
                opacity: particles == ParticleStyle.confetti ? .5 : .4,
                color: dark ? preset.accent(theme.brightness) : Colors.white,
              ),
            ),
          Positioned.fill(
            child: SafeArea(
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
                    if (game.isFinished)
                      _PlayAgainBar(game: game, myUid: myUid),
                  ],
                ),
              },
            ),
          ),
        ],
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
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final mine = game.isMyTurn(myUid);
    final (String text, String emoji) = switch (game) {
      Game(isFinished: true, isDraw: true) => ('It\'s a draw', '🤝'),
      Game(isFinished: true, winner: final w?) when w == myUid => (
        'You won!',
        '🏆',
      ),
      Game(isFinished: true, winner: final w?) when w != myUid => (
        '$partnerName won',
        '🎉',
      ),
      Game(isFinished: true) => ('Game over', '🎉'),
      _ when mine => ('Your turn', ''),
      _ => ('$partnerName\'s turn', ''),
    };

    if (game.isFinished) {
      final preset = PlayLook.iWon(game, myUid)
          ? GradientPreset.gold
          : GradientPreset.festive;
      final b = theme.brightness;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: AnimatedGradientCard(
          preset: preset,
          radius: 22,
          glow: preset.accent(b),
          padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
          border: Border.all(
            color: Colors.white.withValues(alpha: dark ? .18 : .8),
            width: 1.5,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: dark ? .14 : .75),
                  shape: BoxShape.circle,
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: preset.foreground(b),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Center(
        child: GlassPanel(
          dark: dark,
          radius: 30,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (mine)
                RepaintBoundary(
                  child: Pulse(
                    builder: (context, v, _) => Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: .5),
                            blurRadius: 4 + v * 8,
                            spreadRadius: v * 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Icon(
                  Icons.hourglass_top_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: mine ? scheme.onSurface : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
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

    final dark = theme.brightness == Brightness.dark;
    final accent = PlayLook.of(game.type).accent(theme.brightness);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: GlassPanel(
          dark: dark,
          radius: 32,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Bobbing(
                amplitude: 5,
                tilt: .04,
                child: Container(
                  width: 104,
                  height: 104,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: dark ? .12 : .8),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: .3),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Text(
                    game.type.emoji,
                    style: const TextStyle(fontSize: 56),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                invitedMe
                    ? '${widget.partnerName} wants to play'
                    : 'Waiting for ${widget.partnerName}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
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
              if (GameCatalog.setupLine(game) case final setup?) ...[
                const SizedBox(height: 12),
                Text(
                  setup,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
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
          options: GameCatalog.optionsOf(game),
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
