import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/empty_state.dart';
import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/game_catalog.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/providers/play_providers.dart';
import 'package:couple_app/features/play/widgets/play_game_row.dart';
import 'package:couple_app/features/play/widgets/play_head_to_head_card.dart';
import 'package:couple_app/features/play/widgets/play_hub_lists.dart';
import 'package:couple_app/features/play/widgets/play_start_card.dart';
import 'package:couple_app/features/together/widgets/calendar_section_title.dart';

/// The Play tab: what's waiting on whom, games to start, the head-to-head
/// score and recent results.
class PlayHubScreen extends ConsumerStatefulWidget {
  const PlayHubScreen({super.key});

  @override
  ConsumerState<PlayHubScreen> createState() => _PlayHubScreenState();
}

class _PlayHubScreenState extends ConsumerState<PlayHubScreen> {
  late final GameService _service;
  late final String _coupleId;
  late final String _myUid;

  /// Games with an accept / decline in flight.
  final _busyGames = <String>{};

  /// Game types with an invite being sent.
  final _busyTypes = <GameType>{};

  @override
  void initState() {
    super.initState();
    _service = ref.read(gameServiceProvider);
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
  }

  Future<void> _start(GameType type, String partnerUid) async {
    final games = ref.read(gamesProvider).value ?? const <Game>[];
    final open = PlayHubLists.openOf(games, type);
    if (open != null) {
      context.showSnackMessage(
        'You already have a ${type.label} game going. Opening it.',
      );
      await GameCatalog.open(context, open);
      return;
    }
    final options = await GameCatalog.pickOptions(context, type);
    if (options == null || !mounted) return;
    setState(() => _busyTypes.add(type));
    try {
      final id = await _service.invite(
        coupleId: _coupleId,
        type: type,
        me: _myUid,
        invitee: partnerUid,
        state: GameCatalog.newState(
          type,
          inviter: _myUid,
          invitee: partnerUid,
          options: options,
        ),
      );
      if (!mounted) return;
      setState(() => _busyTypes.remove(type));
      await GameCatalog.open(
        context,
        Game(
          id: id,
          type: type,
          status: GameStatus.invited,
          createdBy: _myUid,
          invitee: partnerUid,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _busyTypes.remove(type));
        context.showSnackMessage('Could not start a new game. Try again.');
      }
    }
  }

  Future<void> _accept(Game game) async {
    setState(() => _busyGames.add(game.id));
    try {
      await _service.accept(
        coupleId: _coupleId,
        gameId: game.id,
        me: _myUid,
        firstTurn: GameCatalog.firstTurn(game),
      );
      if (mounted) await GameCatalog.open(context, game);
    } on GameMoveException catch (e) {
      if (mounted) context.showSnackMessage(e.message);
    } catch (_) {
      if (mounted) {
        context.showSnackMessage('Could not reach the game. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busyGames.remove(game.id));
    }
  }

  Future<void> _decline(Game game) async {
    setState(() => _busyGames.add(game.id));
    try {
      await _service.cancel(coupleId: _coupleId, gameId: game.id);
    } on GameMoveException catch (e) {
      if (mounted) context.showSnackMessage(e.message);
    } catch (_) {
      if (mounted) {
        context.showSnackMessage('Could not reach the game. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busyGames.remove(game.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final gamesState = ref.watch(gamesProvider);
    final partnerName = ref.watch(partnerNameProvider);
    final couple = ref.watch(coupleProvider).value;
    final partnerUid = couple?.partnerIdFor(_myUid);
    final games = gamesState.value ?? const <Game>[];
    final loading = !gamesState.hasValue && !gamesState.hasError;
    final failed = !gamesState.hasValue && gamesState.hasError;
    final now = DateTime.now();

    final waitingOnMe = PlayHubLists.waitingOnMe(games, _myUid);
    final waitingOnPartner = PlayHubLists.waitingOnPartner(games, _myUid);
    final recent = PlayHubLists.recent(games);
    final h2hPartner =
        partnerUid ?? (games.isEmpty ? null : games.first.opponentOf(_myUid));
    final anyFinished = games.any((g) => g.isFinished);

    Widget row(Game g, {bool mine = false}) {
      final invitedMe = g.isInvite && g.invitee == _myUid;
      final busy = _busyGames.contains(g.id);
      return PlayGameRow(
        key: ValueKey('game-${g.id}'),
        game: g,
        status: g.isOpen
            ? PlayHubLists.statusText(g, _myUid, partnerName)
            : PlayHubLists.resultText(g, _myUid, partnerName),
        time: PlayHubLists.relativeTime(PlayHubLists.lastActivity(g), now),
        emphasised: mine,
        onTap: busy ? null : () => GameCatalog.open(context, g),
        actions: invitedMe
            ? Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    onPressed: busy ? null : () => _accept(g),
                    child: const Text('Accept'),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(0, 36)),
                    onPressed: busy ? null : () => _decline(g),
                    child: const Text('Not now'),
                  ),
                ],
              )
            : null,
      );
    }

    final children = <Widget>[
      if (loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (failed)
        const EmptyState(
          icon: Icons.cloud_off,
          text: 'Could not load your games.',
          padding: EdgeInsets.symmetric(vertical: 28, horizontal: 32),
        )
      else ...[
        if (waitingOnMe.isNotEmpty) ...[
          const CalendarSectionTitle(label: 'Waiting on you'),
          for (final (i, g) in waitingOnMe.indexed)
            EntranceAnimation(index: i, child: row(g, mine: true)),
        ],
        if (waitingOnPartner.isNotEmpty) ...[
          CalendarSectionTitle(label: 'Waiting on $partnerName'),
          for (final (i, g) in waitingOnPartner.indexed)
            EntranceAnimation(index: i, child: row(g)),
        ],
        if (games.isEmpty) ...[
          if (partnerUid != null)
            _Banner(
              emoji: '🎈',
              text: 'No games yet. Pick one below to challenge $partnerName.',
            ),
        ] else if (waitingOnMe.isEmpty && waitingOnPartner.isEmpty)
          const _Banner(
            emoji: '✨',
            text: 'All caught up. Start something fun below.',
          ),
      ],
      const CalendarSectionTitle(label: 'Start a game'),
      if (partnerUid == null && couple != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'You can start games once $partnerName has joined.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      _StartGrid(
        children: [
          for (final type in GameType.values)
            PlayStartCard(
              key: ValueKey('start-${type.id}'),
              type: type,
              inProgress: PlayHubLists.openOf(games, type) != null,
              busy: _busyTypes.contains(type),
              onTap: partnerUid == null || loading
                  ? null
                  : () => _start(type, partnerUid),
            ),
        ],
      ),
      if (anyFinished && h2hPartner != null) ...[
        const CalendarSectionTitle(label: 'Head to head'),
        PlayHeadToHeadCard(
          games: games,
          myUid: _myUid,
          partnerUid: h2hPartner,
          partnerName: partnerName,
        ),
      ],
      if (recent.isNotEmpty) ...[
        const CalendarSectionTitle(label: 'Recent games'),
        for (final (i, g) in recent.indexed)
          EntranceAnimation(index: i, child: row(g)),
      ],
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Play')),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        children: children,
      ),
    );
  }
}

/// A friendly one-liner card.
class _Banner extends StatelessWidget {
  const _Banner({required this.emoji, required this.text});

  final String emoji;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: AnimatedGradientCard(
        preset: GradientPreset.blush,
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: GradientPreset.blush.foreground(theme.brightness),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two cards per row, each row as tall as its tallest card.
class _StartGrid extends StatelessWidget {
  const _StartGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: children[i]),
                const SizedBox(width: 12),
                Expanded(
                  child: i + 1 < children.length
                      ? children[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(children: rows),
    );
  }
}
