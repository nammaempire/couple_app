import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/core/widgets/motion_policy.dart';
import 'package:couple_app/core/widgets/voice_clip_player.dart';
import 'package:couple_app/features/together/models/love_note.dart';
import 'package:couple_app/features/together/widgets/envelope_art.dart';
import 'package:couple_app/features/together/widgets/note_paper.dart';
import 'package:couple_app/features/together/widgets/note_theme.dart';

/// An opened love note: a sheet of letter paper with a wax seal, a date
/// chip above and glass actions below, drawn over the note's gradient.
///
/// With [reveal], it plays once: the envelope's flap opens, the letter
/// rises out, and the full page settles into place.
class LoveLetterView extends StatefulWidget {
  const LoveLetterView({
    super.key,
    required this.note,
    required this.content,
    required this.isMine,
    required this.partnerName,
    required this.myName,
    this.reveal = false,
    this.status,
    this.actions = const [],
  });

  final LoveNote note;
  final LoveNoteContent content;
  final bool isMine;
  final String partnerName;
  final String myName;
  final bool reveal;

  /// For the sender: whether it has been opened yet.
  final String? status;

  /// Glass chips under the letter.
  final List<Widget> actions;

  @override
  State<LoveLetterView> createState() => _LoveLetterViewState();
}

class _LoveLetterViewState extends State<LoveLetterView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted) return;
    if (widget.reveal && MotionPolicy.enabled(context)) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _seg(double t, double a, double b, [Curve c = Curves.linear]) =>
      c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final look = NoteTheme.of(widget.note);
    final page = _LetterPage(
      note: widget.note,
      content: widget.content,
      isMine: widget.isMine,
      partnerName: widget.partnerName,
      myName: widget.myName,
      look: look,
      status: widget.status,
      actions: widget.actions,
    );

    return AnimatedBuilder(
      animation: _c,
      child: page,
      builder: (context, child) {
        // One tree shape throughout, so the page keeps its state when the
        // reveal ends.
        final t = _c.value;
        final flap = _seg(t, 0, .28, Curves.easeInOut);
        final rise = _seg(t, .25, .55, Curves.easeOutCubic);
        final envFade = 1 - _seg(t, .5, .7);
        final pageIn = _seg(t, .52, 1, Curves.easeOutBack);
        final pageFade = _seg(t, .52, .75);
        return Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: pageFade,
                child: Transform.translate(
                  offset: Offset(0, (1 - pageIn) * 120),
                  child: Transform.scale(scale: .9 + .1 * pageIn, child: child),
                ),
              ),
            ),
            if (envFade > 0)
              Center(
                child: Opacity(
                  opacity: envFade,
                  child: Transform.translate(
                    offset: Offset(0, 40 + 80 * (1 - envFade)),
                    child: EnvelopeArt(
                      preset: look.preset,
                      width: 264,
                      flap: flap,
                      rise: rise,
                      seal: WaxSeal(
                        preset: look.preset,
                        label: widget.note.emoji,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LetterPage extends StatelessWidget {
  const _LetterPage({
    required this.note,
    required this.content,
    required this.isMine,
    required this.partnerName,
    required this.myName,
    required this.look,
    required this.status,
    required this.actions,
  });

  final LoveNote note;
  final LoveNoteContent content;
  final bool isMine;
  final String partnerName;
  final String myName;
  final NoteTheme look;
  final String? status;
  final List<Widget> actions;

  static const _bodySize = 19.0;
  static const _bodyHeight = 1.65;

  String _dateChip(DateTime now) {
    final at = note.deliverAt;
    final verb = isMine
        ? (note.isScheduled(now) ? 'Arrives' : 'Sent')
        : 'Delivered';
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(at.year, at.month, at.day)).inDays;
    final ago = switch (days) {
      < 0 => days == -1 ? 'tomorrow' : 'in ${-days} days',
      0 => 'today',
      1 => 'yesterday',
      < 7 => '$days days ago',
      < 14 => 'a week ago',
      < 60 => '${days ~/ 7} weeks ago',
      _ => '${days ~/ 30} months ago',
    };
    final date = at.year == now.year
        ? DateFormat.MMMd().format(at)
        : DateFormat.yMMMd().format(at);
    return '$verb $date · $ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final dark = look.preset.isDarkIn(b);
    final fg = look.preset.foreground(b);
    final sender = isMine ? myName : partnerName;
    final sealLabel = note.kind == NoteKind.openWhen
        ? note.emoji
        : (sender.isEmpty ? '♥' : sender.characters.first.toUpperCase());

    final bodyStyle = noteSerif(
      theme.textTheme.bodyLarge,
    ).copyWith(fontSize: _bodySize, height: _bodyHeight, color: NoteInk.ink);

    final paper = NotePaper(
      angle: -.012,
      padding: const EdgeInsets.fromLTRB(26, 46, 26, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            note.envelopeTitle,
            style: noteSerif(theme.textTheme.headlineSmall).copyWith(
              color: NoteInk.ink,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isMine ? 'To $partnerName' : 'From $partnerName',
            style: theme.textTheme.labelLarge?.copyWith(
              color: look.preset.ink,
              letterSpacing: .4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            height: 1,
            width: 56,
            color: look.preset.ink.withValues(alpha: .4),
          ),
          const SizedBox(height: 16),
          if (content.body.isNotEmpty)
            RuledLines(
              lineHeight: _bodySize * _bodyHeight,
              child: SizedBox(
                width: double.infinity,
                child: SelectableText(content.body, style: bodyStyle),
              ),
            ),
          const SizedBox(height: 28),
          Align(
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'With love,',
                  style: noteSerif(theme.textTheme.bodyLarge).copyWith(
                    fontStyle: FontStyle.italic,
                    color: NoteInk.inkMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sender,
                  style: noteSerif(theme.textTheme.headlineSmall).copyWith(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    color: look.preset.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, box.maxHeight - 32),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GlassPanel(
                  dark: dark,
                  radius: 30,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.mail_outline_rounded, size: 16, color: fg),
                      const SizedBox(width: 6),
                      Text(
                        _dateChip(DateTime.now()),
                        style: theme.textTheme.labelLarge?.copyWith(color: fg),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 28),
                      child: paper,
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: WaxSeal(
                          preset: look.preset,
                          label: sealLabel,
                          size: 58,
                          textStyle: note.kind == NoteKind.openWhen
                              ? const TextStyle(fontSize: 26)
                              : noteSerif(
                                  theme.textTheme.headlineSmall,
                                ).copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontStyle: FontStyle.italic,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (content.voiceUrl != null) ...[
                  const SizedBox(height: 18),
                  GlassPanel(
                    dark: dark,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.graphic_eq_rounded, size: 18, color: fg),
                            const SizedBox(width: 8),
                            Text(
                              'A voice letter from '
                              '${isMine ? 'you' : partnerName}',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: fg,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        VoiceClipPlayer(
                          clipId: 'note-${note.id}',
                          url: content.voiceUrl,
                          duration: note.voiceDurationMs == null
                              ? null
                              : Duration(milliseconds: note.voiceDurationMs!),
                          color: fg,
                          maxWidth: 420,
                        ),
                      ],
                    ),
                  ),
                ],
                if (status != null) ...[
                  const SizedBox(height: 18),
                  Text(
                    status!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: look.preset.foregroundMuted(b),
                    ),
                  ),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
