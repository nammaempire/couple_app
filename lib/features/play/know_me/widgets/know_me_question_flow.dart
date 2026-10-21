import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:couple_app/core/widgets/entrance_animation.dart';

import 'package:couple_app/features/play/know_me/know_me_question.dart';
import 'package:couple_app/features/play/widgets/play_look.dart';

/// Steps through the quiz one question at a time (with back / next), then
/// shows a review of every pick before [onSubmit].
///
/// Used both for answering about yourself ([aboutName] null) and for
/// guessing about your partner ([aboutName] is their name).
class KnowMeQuestionFlow extends StatefulWidget {
  const KnowMeQuestionFlow({
    super.key,
    required this.questions,
    required this.title,
    required this.submitLabel,
    required this.onSubmit,
    this.aboutName,
    this.busy = false,
  });

  final List<KnowMeQuestion> questions;
  final String? aboutName;

  /// One line above the progress bar ("Answer about yourself").
  final String title;
  final String submitLabel;
  final void Function(List<int> picks) onSubmit;

  /// Disables input while a move is in flight.
  final bool busy;

  @override
  State<KnowMeQuestionFlow> createState() => _KnowMeQuestionFlowState();
}

class _KnowMeQuestionFlowState extends State<KnowMeQuestionFlow> {
  late final List<int?> _picks = List<int?>.filled(
    widget.questions.length,
    null,
  );

  /// The question on screen; == questions.length for the review.
  int _index = 0;

  int get _count => widget.questions.length;
  bool get _reviewing => _index >= _count;
  bool get _complete => _picks.every((p) => p != null);

  void _pick(int option) {
    if (widget.busy) return;
    HapticFeedback.selectionClick();
    setState(() => _picks[_index] = option);
  }

  void _go(int index) => setState(() => _index = index.clamp(0, _count));

  void _submit() {
    if (!_complete || widget.busy) return;
    widget.onSubmit([for (final p in _picks) p!]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _reviewing ? 1.0 : (_index + 1) / _count;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    _reviewing ? 'Review' : '${_index + 1}/$_count',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TweenAnimationBuilder<double>(
                tween: Tween(end: progress),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                builder: (context, value, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: value, minHeight: 6),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0.04, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: _reviewing
                ? _Review(
                    key: const ValueKey('review'),
                    questions: widget.questions,
                    picks: _picks,
                    aboutName: widget.aboutName,
                    onEdit: widget.busy ? null : _go,
                  )
                : _QuestionPage(
                    key: ValueKey(_index),
                    question: widget.questions[_index],
                    aboutName: widget.aboutName,
                    picked: _picks[_index],
                    onPick: widget.busy ? null : _pick,
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _index == 0 || widget.busy
                      ? null
                      : () => _go(_index - 1),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _reviewing
                    ? FilledButton.icon(
                        onPressed: _complete && !widget.busy ? _submit : null,
                        icon: widget.busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(widget.submitLabel),
                      )
                    : FilledButton.icon(
                        onPressed: _picks[_index] == null || widget.busy
                            ? null
                            : () => _go(_index + 1),
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: Text(_index == _count - 1 ? 'Review' : 'Next'),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuestionPage extends StatelessWidget {
  const _QuestionPage({
    super.key,
    required this.question,
    required this.aboutName,
    required this.picked,
    required this.onPick,
  });

  final KnowMeQuestion question;
  final String? aboutName;
  final int? picked;
  final ValueChanged<int>? onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            question.textFor(aboutName: aboutName),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < question.options.length; i++)
            EntranceAnimation(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _OptionTile(
                  letter: String.fromCharCode(65 + i),
                  text: question.options[i],
                  selected: picked == i,
                  onTap: onPick == null ? null : () => onPick!(i),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.letter,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String letter;
  final String text;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = scheme.onSurface;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: selected
                  ? (dark
                        ? scheme.surface.withValues(alpha: .85)
                        : Colors.white.withValues(alpha: .95))
                  : Colors.white.withValues(alpha: dark ? .08 : .5),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? scheme.primary
                    : Colors.white.withValues(alpha: dark ? .16 : .85),
                width: selected ? 2 : 1,
              ),
              boxShadow: [
                if (selected)
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: .2),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
              ],
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? scheme.primary
                        : Colors.white.withValues(alpha: dark ? .12 : .85),
                  ),
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: fg),
                  ),
                ),
                AnimatedScale(
                  scale: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({
    super.key,
    required this.questions,
    required this.picks,
    required this.aboutName,
    required this.onEdit,
  });

  final List<KnowMeQuestion> questions;
  final List<int?> picks;
  final String? aboutName;
  final ValueChanged<int>? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: questions.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            child: Text(
              'All set? Tap any answer to change it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final index = i - 1;
        final q = questions[index];
        final pick = picks[index];
        return Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: PlayLook.panel(context, light: .7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: onEdit == null ? null : () => onEdit!(index),
            title: Text(q.textFor(aboutName: aboutName)),
            subtitle: Text(
              pick == null ? 'Not answered yet' : q.options[pick],
              style: theme.textTheme.titleSmall?.copyWith(
                color: pick == null
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: const Icon(Icons.edit_outlined, size: 20),
          ),
        );
      },
    );
  }
}
