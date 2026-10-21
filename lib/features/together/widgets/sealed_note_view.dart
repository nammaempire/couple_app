import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/features/together/models/love_note.dart';
import 'package:couple_app/features/together/widgets/envelope_art.dart';
import 'package:couple_app/features/together/widgets/note_theme.dart';

/// What the recipient sees before a scheduled note arrives: a floating
/// sealed envelope, a live countdown and a ring filling up from when it was
/// sent to when it opens. Drawn over the note's gradient.
class SealedNoteView extends StatefulWidget {
  const SealedNoteView({
    super.key,
    required this.note,
    required this.partnerName,
  });

  final LoveNote note;
  final String partnerName;

  /// "2d 14h 32m", dropping leading zero units.
  static String countdown(Duration left) {
    if (left.inMinutes < 1) return 'Any moment';
    final d = left.inDays;
    final h = left.inHours % 24;
    final m = left.inMinutes % 60;
    return [if (d > 0) '${d}d', if (d > 0 || h > 0) '${h}h', '${m}m'].join(' ');
  }

  @override
  State<SealedNoteView> createState() => _SealedNoteViewState();
}

class _SealedNoteViewState extends State<SealedNoteView> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final note = widget.note;
    final look = NoteTheme.of(note);
    final fg = look.preset.foreground(b);
    final muted = look.preset.foregroundMuted(b);
    final dark = look.preset.isDarkIn(b);
    final accent = look.preset.accent(Brightness.light);

    final now = DateTime.now();
    final left = note.deliverAt.difference(now);
    final from = note.createdAt;
    final progress = from == null || !note.deliverAt.isAfter(from)
        ? null
        : (now.difference(from).inSeconds /
                  note.deliverAt.difference(from).inSeconds)
              .clamp(0.0, 1.0);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, box.maxHeight - 32),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Bobbing(
                  amplitude: 8,
                  tilt: .02,
                  child: SizedBox(
                    width: 264,
                    height: 264 * EnvelopeArt.aspect + 30,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topCenter,
                      children: [
                        Positioned(
                          top: 30,
                          child: EnvelopeArt(preset: look.preset, width: 264),
                        ),
                        // The lock sits where the seal would, ringed by
                        // how far along the wait is.
                        Positioned(
                          top: 30 + 264 * EnvelopeArt.aspect * .56 - 46,
                          child: _LockBadge(
                            accent: accent,
                            progress: progress,
                            ringColor: dark ? Colors.white : accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  'OPENS IN',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: muted,
                    letterSpacing: 2.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  SealedNoteView.countdown(left),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '${widget.partnerName} sealed this for you.',
                  textAlign: TextAlign.center,
                  style: noteSerif(
                    theme.textTheme.titleLarge,
                  ).copyWith(color: fg, fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 6),
                Text(
                  'Opens ${DateFormat.MMMd().add_jm().format(note.deliverAt)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
                const SizedBox(height: 26),
                GlassPanel(
                  dark: dark,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(note.emoji, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          note.envelopeTitle,
                          style: noteSerif(
                            theme.textTheme.titleMedium,
                          ).copyWith(color: fg, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (note.hasVoice) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.mic_none_rounded, size: 18, color: fg),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'No peeking — it unlocks on its own.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LockBadge extends StatelessWidget {
  const _LockBadge({
    required this.accent,
    required this.progress,
    required this.ringColor,
  });

  final Color accent;
  final double? progress;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    return Pulse(
      duration: const Duration(milliseconds: 1600),
      builder: (context, v, child) => SizedBox.square(
        dimension: 92,
        child: CustomPaint(
          painter: _RingPainter(progress: progress, color: ringColor),
          child: Center(
            child: Transform.scale(
              scale: 1 + .06 * v,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-.3, -.4),
                    colors: [Color.lerp(accent, Colors.white, .35)!, accent],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: .35 + .3 * v),
                      blurRadius: 16 + 14 * v,
                      spreadRadius: 2 + 4 * v,
                    ),
                  ],
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
      child: const Icon(Icons.lock_rounded, color: Colors.white, size: 28),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});

  final double? progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = color.withValues(alpha: .22),
    );
    final p = progress;
    if (p == null || p <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * p,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}
