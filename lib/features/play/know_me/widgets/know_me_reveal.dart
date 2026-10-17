import 'package:flutter/material.dart';

import 'package:couple_app/features/play/know_me/know_me_logic.dart';
import 'package:couple_app/features/play/know_me/know_me_question.dart';

/// The result, for both players: the score, a verdict, and every answer
/// next to its guess.
class KnowMeReveal extends StatelessWidget {
  const KnowMeReveal({
    super.key,
    required this.questions,
    required this.answers,
    required this.guesses,
    required this.score,
    required this.total,
    required this.iAmSubject,
    required this.partnerName,
  });

  final List<KnowMeQuestion> questions;
  final List<int> answers;
  final List<int> guesses;
  final int score;
  final int total;

  /// Whether the quiz was about me (so my partner did the guessing).
  final bool iAmSubject;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verdict = KnowMeLogic.verdict(score, total);
    final summary = iAmSubject
        ? '$partnerName guessed $score of your $total answers'
        : 'You guessed $score of $partnerName\'s $total answers';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        Card(
          margin: EdgeInsets.zero,
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.4, end: 1),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.elasticOut,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Text(
                    verdict.emoji,
                    style: const TextStyle(fontSize: 52),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$score / $total',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  verdict.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < questions.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AnswerCard(
              question: questions[i],
              answer: i < answers.length ? answers[i] : null,
              guess: i < guesses.length ? guesses[i] : null,
              iAmSubject: iAmSubject,
              partnerName: partnerName,
            ),
          ),
      ],
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    required this.question,
    required this.answer,
    required this.guess,
    required this.iAmSubject,
    required this.partnerName,
  });

  final KnowMeQuestion question;
  final int? answer;
  final int? guess;
  final bool iAmSubject;
  final String partnerName;

  String _option(int? i) => i == null || i < 0 || i >= question.options.length
      ? '—'
      : question.options[i];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final right = answer != null && answer == guess;
    final answerLabel = iAmSubject ? 'You said' : '$partnerName said';
    final guessLabel = iAmSubject ? '$partnerName guessed' : 'You guessed';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: right ? 'Correct' : 'Missed',
              child: CircleAvatar(
                radius: 14,
                backgroundColor: right
                    ? scheme.primary
                    : scheme.surfaceContainerHighest,
                // Icons rather than ✓/✗ text, which some fonts lack.
                child: Icon(
                  right ? Icons.check_rounded : Icons.close_rounded,
                  size: 18,
                  color: right ? scheme.onPrimary : scheme.error,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    iAmSubject ? question.self : question.about(partnerName),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  _Line(label: answerLabel, value: _option(answer)),
                  _Line(
                    label: guessLabel,
                    value: _option(guess),
                    color: right ? scheme.primary : scheme.error,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            TextSpan(
              text: value,
              style: TextStyle(fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}
