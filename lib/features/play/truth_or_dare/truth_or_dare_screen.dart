import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/providers/play_providers.dart';
import 'package:couple_app/features/play/truth_or_dare/truth_or_dare_card_view.dart';
import 'package:couple_app/features/play/truth_or_dare/truth_or_dare_cards.dart';
import 'package:couple_app/features/play/truth_or_dare/truth_or_dare_logic.dart';
import 'package:couple_app/features/play/widgets/game_scaffold.dart';

/// Truth or Dare: take turns drawing a card; the partner judges whether
/// it was done. All rules live in [TruthOrDareLogic].
class TruthOrDareScreen extends StatelessWidget {
  const TruthOrDareScreen({super.key, required this.gameId});

  final String gameId;

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      gameId: gameId,
      builder: (context, game, myUid) => _Body(game: game, myUid: myUid),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.game, required this.myUid});

  final Game game;
  final String myUid;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  late final GameService _service;
  late final String _coupleId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service = ref.read(gameServiceProvider);
    _coupleId = ref.read(currentCoupleIdProvider);
  }

  Future<void> _move(Map<String, dynamic> Function(Game game) apply) async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      await _service.takeTurn(
        coupleId: _coupleId,
        gameId: widget.game.id,
        me: widget.myUid,
        apply: apply,
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

  void _choose(TruthOrDareKind? kind) =>
      _move((game) => TruthOrDareLogic.choose(game, widget.myUid, kind));

  void _judge({required bool done}) =>
      _move((game) => TruthOrDareLogic.judge(game, widget.myUid, done: done));

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final me = widget.myUid;
    final partner = game.opponentOf(me);
    final partnerName = ref.watch(partnerNameProvider);
    final s = TruthOrDareState.of(game);

    if (game.isFinished) {
      return _Summary(game: game, myUid: me, partnerName: partnerName);
    }

    final myTurn = game.isMyTurn(me);
    final chooser = TruthOrDareLogic.chooserOf(game);
    final judging = s.phase == TruthOrDareLogic.phaseJudge;

    final Widget actions;
    if (!judging && myTurn) {
      actions = _ChooseActions(busy: _busy, onChoose: _choose);
    } else if (!judging) {
      actions = _Waiting(text: '$partnerName is choosing…');
    } else if (myTurn) {
      actions = _JudgeActions(
        busy: _busy,
        partnerName: partnerName,
        kind: s.card?.kind,
        onJudge: _judge,
      );
    } else {
      actions = Column(
        children: [
          Text(
            s.card?.kind == TruthOrDareKind.dare ? 'Your dare!' : 'Your truth!',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const _Hint(text: 'Do it in chat or on a call'),
          const SizedBox(height: 16),
          _Waiting(text: '$partnerName is deciding if you did it…'),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0, constraints.maxHeight - 40),
          ),
          child: Column(
            children: [
              _RoundAndScore(
                round: s.round,
                rounds: s.rounds,
                mine: s.doneBy(me),
                theirs: s.doneBy(partner),
                partnerName: partnerName,
                chooserIsMe: chooser == me,
              ),
              const SizedBox(height: 24),
              TruthOrDareCardView(card: judging ? s.card : null),
              const SizedBox(height: 28),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: KeyedSubtree(
                  key: ValueKey('${s.phase}-$myTurn'),
                  child: actions,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Round 3 of 10" and the done counts.
class _RoundAndScore extends StatelessWidget {
  const _RoundAndScore({
    required this.round,
    required this.rounds,
    required this.mine,
    required this.theirs,
    required this.partnerName,
    required this.chooserIsMe,
  });

  final int round;
  final int rounds;
  final int mine;
  final int theirs;
  final String partnerName;
  final bool chooserIsMe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        Text(
          'Round $round of $rounds',
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 160,
            child: LinearProgressIndicator(
              value: rounds == 0 ? 0 : (round - 1) / rounds,
              minHeight: 4,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: _ScoreChip(label: 'You', count: mine, active: chooserIsMe),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('·', style: theme.textTheme.titleLarge),
            ),
            Flexible(
              child: _ScoreChip(
                label: partnerName,
                count: theirs,
                active: !chooserIsMe,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({
    required this.label,
    required this.count,
    required this.active,
  });

  final String label;
  final int count;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: active
            ? (dark
                  ? scheme.surface.withValues(alpha: .85)
                  : Colors.white.withValues(alpha: .92))
            : Colors.white.withValues(alpha: dark ? .08 : .4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active
              ? scheme.primary
              : Colors.white.withValues(alpha: dark ? .16 : .7),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          const SizedBox(width: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, a) =>
                ScaleTransition(scale: a, child: child),
            child: Text(
              '$count',
              key: ValueKey(count),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChooseActions extends StatelessWidget {
  const _ChooseActions({required this.busy, required this.onChoose});

  final bool busy;
  final void Function(TruthOrDareKind? kind) onChoose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final big = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(64),
      textStyle: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
    return Column(
      children: [
        Text('Pick one', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                style: big,
                onPressed: busy ? null : () => onChoose(TruthOrDareKind.truth),
                child: const Text('💬 Truth'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: big.copyWith(
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.disabled)
                        ? null
                        : scheme.tertiary,
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.disabled)
                        ? null
                        : scheme.onTertiary,
                  ),
                ),
                onPressed: busy ? null : () => onChoose(TruthOrDareKind.dare),
                child: const Text('✨ Dare'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: busy ? null : () => onChoose(null),
          icon: const Icon(Icons.shuffle_rounded),
          label: const Text('Surprise me'),
        ),
      ],
    );
  }
}

class _JudgeActions extends StatelessWidget {
  const _JudgeActions({
    required this.busy,
    required this.partnerName,
    required this.kind,
    required this.onJudge,
  });

  final bool busy;
  final String partnerName;
  final TruthOrDareKind? kind;
  final void Function({required bool done}) onJudge;

  @override
  Widget build(BuildContext context) {
    final verb = kind == TruthOrDareKind.dare ? 'do it' : 'answer';
    return Column(
      children: [
        Text(
          'Did $partnerName $verb?',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        _Hint(text: '$partnerName does it in chat or on a call'),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: busy ? null : () => onJudge(done: false),
                child: const Text('Skipped'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: busy ? null : () => onJudge(done: true),
                child: const Text('Done 💞'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.chat_bubble_outline_rounded, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Flexible(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

/// After the last round: who was most daring, the counts and the last
/// few cards.
class _Summary extends StatelessWidget {
  const _Summary({
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
    final s = TruthOrDareState.of(game);
    final partner = game.opponentOf(myUid);
    final mostDaring = TruthOrDareLogic.mostDaring(game.players, s.done);
    final headline = mostDaring == Game.draw
        ? 'You\'re both equally daring 💞'
        : mostDaring == myUid
        ? 'Most daring: you! ✨'
        : mostDaring == partner
        ? 'Most daring: $partnerName ✨'
        : 'That\'s a wrap 💞';
    final recent = s.history.reversed.take(5).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      children: [
        const Center(child: Text('🎉', style: TextStyle(fontSize: 52))),
        const SizedBox(height: 8),
        Text(
          headline,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _CountCard(
                name: 'You',
                done: s.doneBy(myUid),
                skipped: s.skippedBy(myUid),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CountCard(
                name: partnerName,
                done: s.doneBy(partner),
                skipped: s.skippedBy(partner),
              ),
            ),
          ],
        ),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Last few cards', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final h in recent) _HistoryTile(entry: h, myUid: myUid),
        ],
        const SizedBox(height: 8),
        Text(
          'Thanks for playing together.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.name,
    required this.done,
    required this.skipped,
  });

  final String name;
  final int done;
  final int skipped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '$done done',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
              ),
            ),
            Text('$skipped skipped', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.entry, required this.myUid});

  final Map<String, dynamic> entry;
  final String myUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnerName = ref.watch(partnerNameProvider);
    final kind = TruthOrDareKind.fromId(entry['kind']);
    final id = entry['id'];
    final card = id is String ? TruthOrDareCards.byId(id) : null;
    final who = entry['chooser'] == myUid ? 'You' : partnerName;
    final done = entry['result'] == TruthOrDareLogic.resultDone;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Text(
        kind == TruthOrDareKind.dare ? '✨' : '💬',
        style: const TextStyle(fontSize: 22),
      ),
      title: Text(
        card?.text ?? (kind?.label ?? 'A card'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('$who · ${done ? 'done 💞' : 'skipped'}'),
    );
  }
}
