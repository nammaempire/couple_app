import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/features/together/models/love_note.dart';
import 'package:couple_app/features/together/widgets/envelope_art.dart';
import 'package:couple_app/features/together/widgets/note_theme.dart';

/// Delivered "Open when…" envelopes, two per row, each on its own themed
/// gradient and gently floating. Opened ones rest, a little faded.
class OpenWhenEnvelopeGrid extends StatelessWidget {
  const OpenWhenEnvelopeGrid({
    super.key,
    required this.notes,
    required this.onOpen,
  });

  final List<LoveNote> notes;
  final ValueChanged<LoveNote> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 1.02,
      children: [
        for (final (i, n) in notes.indexed)
          Builder(
            builder: (context) {
              final preset = NoteTheme.of(n).preset;
              final fg = preset.foreground(b);
              final tile = AnimatedGradientCard(
                preset: preset,
                onTap: () => onOpen(n),
                animate: !n.isOpened,
                sheen: !n.isOpened,
                radius: 22,
                padding: EdgeInsets.zero,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // The envelope's flap.
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _FlapPainter(
                          color: Colors.white.withValues(
                            alpha: preset.isDarkIn(b) ? .1 : .45,
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: const Alignment(0, -.3),
                      child: WaxSeal(preset: preset, label: n.emoji, size: 44),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.envelopeTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: noteSerif(theme.textTheme.titleSmall)
                                .copyWith(
                                  color: fg,
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                n.isOpened
                                    ? Icons.drafts_outlined
                                    : Icons.mail_rounded,
                                size: 14,
                                color: preset.foregroundMuted(b),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                n.isOpened ? 'Opened' : 'Sealed',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: preset.foregroundMuted(b),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              return n.isOpened
                  ? Opacity(opacity: .78, child: tile)
                  : Bobbing(
                      amplitude: 3,
                      phase: i * .37,
                      duration: const Duration(milliseconds: 3600),
                      child: tile,
                    );
            },
          ),
      ],
    );
  }
}

class _FlapPainter extends CustomPainter {
  _FlapPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height * .36)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height * .36)
        ..lineTo(size.width, 0),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withValues(alpha: (color.a * 1.6).clamp(0, 1)),
    );
  }

  @override
  bool shouldRepaint(_FlapPainter old) => old.color != color;
}
