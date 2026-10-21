import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';

import 'package:couple_app/features/home/models/daily_question.dart';

/// Today's shared prompt. Answers stay hidden until both have replied.
class DailyQuestionCard extends StatefulWidget {
  const DailyQuestionCard({
    super.key,
    required this.entry,
    required this.myUid,
    required this.partnerUid,
    required this.partnerName,
    required this.onAnswer,
    this.streak = 0,
  });

  final DailyQuestionEntry entry;
  final String myUid;
  final String? partnerUid;
  final String partnerName;
  final Future<void> Function(String text) onAnswer;

  /// Consecutive days both answered. Shown gently from 2 days, never as a
  /// warning — the question should not feel like an obligation.
  final int streak;

  @override
  State<DailyQuestionCard> createState() => _DailyQuestionCardState();
}

class _DailyQuestionCardState extends State<DailyQuestionCard> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_controller.text.trim().isEmpty) return;
    setState(() => _sending = true);
    await widget.onAnswer(_controller.text);
    if (mounted) {
      _controller.clear();
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = widget.entry;
    final iAnswered = entry.hasAnswered(widget.myUid);

    return AnimatedGradientCard(
      preset: GradientPreset.peach,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 18,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                'Question of the day',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const Spacer(),
              if (widget.streak >= 2)
                Tooltip(
                  message: 'Days in a row you have both answered',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: .7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '🔥 ${widget.streak} days',
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            entry.prompt,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),

          if (!iAnswered) ...[
            TextField(
              controller: _controller,
              minLines: 2,
              maxLines: 5,
              maxLength: 400,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Your answer…',
                counterText: '',
                fillColor: theme.colorScheme.surface,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _sending ? null : _submit,
              child: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Answer'),
            ),
          ] else if (!entry.isUnlocked) ...[
            _LockedNote(partnerName: widget.partnerName),
          ] else ...[
            _AnswerBlock(
              label: 'You said',
              text: entry.answerFor(widget.myUid)?.text ?? '',
            ),
            const SizedBox(height: 12),
            _AnswerBlock(
              label: '${widget.partnerName} said',
              text: widget.partnerUid == null
                  ? ''
                  : entry.answerFor(widget.partnerUid!)?.text ?? '',
              highlight: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _LockedNote extends StatelessWidget {
  const _LockedNote({required this.partnerName});

  final String partnerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.lock_outline, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text('Answer saved', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'You\'ll both see the answers once $partnerName replies.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswerBlock extends StatelessWidget {
  const _AnswerBlock({
    required this.label,
    required this.text,
    this.highlight = false,
  });

  final String label;
  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight
            ? theme.colorScheme.primary.withValues(alpha: .12)
            : theme.colorScheme.surface.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
        ],
      ),
    );
  }
}
