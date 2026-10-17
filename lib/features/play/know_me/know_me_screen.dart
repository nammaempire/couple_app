import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/empty_state.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/know_me/know_me_logic.dart';
import 'package:couple_app/features/play/know_me/know_me_providers.dart';
import 'package:couple_app/features/play/know_me/know_me_service.dart';
import 'package:couple_app/features/play/know_me/widgets/know_me_question_flow.dart';
import 'package:couple_app/features/play/know_me/widgets/know_me_reveal.dart';
import 'package:couple_app/features/play/know_me/widgets/know_me_waiting.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/providers/play_providers.dart';
import 'package:couple_app/features/play/widgets/game_scaffold.dart';

/// "How well do you know me?": one partner answers about themselves, the
/// other guesses, then both see how well they did.
class KnowMeScreen extends StatelessWidget {
  const KnowMeScreen({super.key, required this.gameId});

  final String gameId;

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      gameId: gameId,
      builder: (context, game, myUid) => _KnowMeBody(game: game, myUid: myUid),
    );
  }
}

class _KnowMeBody extends ConsumerStatefulWidget {
  const _KnowMeBody({required this.game, required this.myUid});

  final Game game;
  final String myUid;

  @override
  ConsumerState<_KnowMeBody> createState() => _KnowMeBodyState();
}

class _KnowMeBodyState extends ConsumerState<_KnowMeBody> {
  static const _moveFailed = 'Could not make that move. Check your connection.';
  static const _revealFailed =
      'Could not reveal the results. Check your connection.';

  late final GameService _games;
  late final KnowMeService _knowMe;
  late final String _coupleId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _games = ref.read(gameServiceProvider);
    _knowMe = ref.read(knowMeServiceProvider);
    _coupleId = ref.read(currentCoupleIdProvider);
  }

  /// Runs [action] with input disabled; shows [failure] (or the move's own
  /// message) if it throws. Returns whether it succeeded.
  Future<bool> _run(Future<void> Function() action, String failure) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      return true;
    } on GameMoveException catch (e) {
      if (mounted) context.showSnackMessage(e.message);
    } catch (_) {
      if (mounted) context.showSnackMessage(failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return false;
  }

  Future<void> _submitAnswers(List<int> answers) async {
    await _run(
      () => _knowMe.submitAnswers(
        coupleId: _coupleId,
        gameId: widget.game.id,
        me: widget.myUid,
        answers: answers,
      ),
      _moveFailed,
    );
  }

  Future<void> _submitGuesses(List<int> guesses) async {
    final me = widget.myUid;
    final locked = await _run(
      () => _games.takeTurn(
        coupleId: _coupleId,
        gameId: widget.game.id,
        me: me,
        apply: (game) => KnowMeLogic.lockGuesses(game, me, guesses),
      ),
      _moveFailed,
    );
    if (locked && mounted) await _reveal();
  }

  /// Reads the secret answers (allowed once guesses are locked) and copies
  /// them into the game, finishing it. Safe to retry.
  Future<void> _reveal() async {
    final me = widget.myUid;
    final gameId = widget.game.id;
    await _run(() async {
      final answers = await _knowMe.readAnswers(
        coupleId: _coupleId,
        gameId: gameId,
      );
      await _games.takeTurn(
        coupleId: _coupleId,
        gameId: gameId,
        me: me,
        apply: (game) => KnowMeLogic.reveal(game, me, answers),
      );
    }, _revealFailed);
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final myUid = widget.myUid;
    final partnerName = ref.watch(partnerNameProvider);
    final questions = KnowMeLogic.questionsOf(game);

    if (questions == null) {
      return const EmptyState(
        icon: Icons.system_update_outlined,
        text: 'This quiz needs a newer version of the app.',
        padding: EdgeInsets.all(32),
      );
    }

    final phase = KnowMeLogic.phaseOf(game);
    final iAmSubject = KnowMeLogic.subjectOf(game) == myUid;
    final myTurn = game.isMyTurn(myUid);

    final Widget body = switch (phase) {
      KnowMePhase.answering when iAmSubject && myTurn => KnowMeQuestionFlow(
        key: const ValueKey('answering'),
        questions: questions,
        title: 'Answer about yourself',
        submitLabel: 'Send answers',
        busy: _busy,
        onSubmit: _submitAnswers,
      ),
      KnowMePhase.answering => KnowMeWaiting(
        key: const ValueKey('waitAnswering'),
        emoji: '✍️',
        title: '$partnerName is answering about themselves…',
        message: 'Then it\'s your turn to guess. We\'ll let you know.',
      ),
      KnowMePhase.guessing when !iAmSubject && myTurn => KnowMeQuestionFlow(
        key: const ValueKey('guessing'),
        questions: questions,
        aboutName: partnerName,
        title: 'Guess $partnerName\'s answers',
        submitLabel: 'Lock in guesses',
        busy: _busy,
        onSubmit: _submitGuesses,
      ),
      KnowMePhase.guessing => KnowMeWaiting(
        key: const ValueKey('waitGuessing'),
        emoji: '🤔',
        title: '$partnerName is guessing your answers…',
        message: 'Your answers are safe. You\'ll both see the results soon.',
      ),
      KnowMePhase.revealing when !iAmSubject && myTurn => KnowMeWaiting(
        key: const ValueKey('reveal'),
        emoji: '🔒',
        title: 'Your guesses are locked in',
        message: 'Let\'s see how well you know $partnerName.',
        action: FilledButton.icon(
          onPressed: _busy ? null : _reveal,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome_rounded),
          label: const Text('Reveal results'),
        ),
      ),
      KnowMePhase.revealing => KnowMeWaiting(
        key: const ValueKey('waitReveal'),
        emoji: '🎁',
        title: '$partnerName locked in their guesses',
        message: 'The results are on their way…',
      ),
      KnowMePhase.finished => KnowMeReveal(
        key: const ValueKey('finished'),
        questions: questions,
        answers: KnowMeLogic.answers(game),
        guesses: KnowMeLogic.guesses(game),
        score: KnowMeLogic.scoreOf(game),
        total: KnowMeLogic.totalOf(game),
        iAmSubject: iAmSubject,
        partnerName: partnerName,
      ),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: body,
    );
  }
}
