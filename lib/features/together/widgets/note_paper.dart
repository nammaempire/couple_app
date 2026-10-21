import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ink and paper colours for letters. The paper stays warm cream in both
/// themes (a lit page in the dark), so the ink is always dark.
abstract final class NoteInk {
  static Color paper(Brightness b) =>
      b == Brightness.dark ? const Color(0xFFF6EFE3) : const Color(0xFFFFFCF6);
  static const ink = Color(0xFF3A2A26);
  static const inkMuted = Color(0xFF7A6560);
  static const rule = Color(0x22B0607A);
  static const margin = Color(0x55E0708C);
}

/// A sheet of warm, lightly textured letter paper with a soft shadow.
class NotePaper extends StatelessWidget {
  const NotePaper({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 8, 18, 8),
    this.angle = 0,
    this.margin = false,
    this.radius = 14,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// A slight tilt in radians, like a letter laid on a table.
  final double angle;

  /// Draw a rose margin line down the left.
  final bool margin;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    Widget paper = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: b == Brightness.dark ? .4 : .12,
            ),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CustomPaint(
          painter: _PaperPainter(color: NoteInk.paper(b), margin: margin),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (angle != 0) paper = Transform.rotate(angle: angle, child: paper);
    return paper;
  }
}

class _PaperPainter extends CustomPainter {
  _PaperPainter({required this.color, required this.margin});

  final Color color;
  final bool margin;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = color);
    // A faint warm vignette towards the edges.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 1.1,
          colors: [
            Colors.transparent,
            const Color(0xFFEBDCC6).withValues(alpha: .16),
          ],
        ).createShader(rect),
    );
    // Fibres: tiny deterministic speckles.
    final r = math.Random(11);
    final speck = Paint()
      ..color = const Color(0xFFB89A7A).withValues(alpha: .07);
    final n = (size.width * size.height / 900).clamp(0, 600).toInt();
    for (var i = 0; i < n; i++) {
      canvas.drawCircle(
        Offset(r.nextDouble() * size.width, r.nextDouble() * size.height),
        .4 + r.nextDouble() * .6,
        speck,
      );
    }
    if (margin) {
      canvas.drawLine(
        const Offset(30, 0),
        Offset(30, size.height),
        Paint()
          ..color = NoteInk.margin
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_PaperPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.margin != margin;
}

/// Faint ruled lines behind text, spaced at the text's line height so the
/// words sit on them.
class RuledLines extends StatelessWidget {
  const RuledLines({
    super.key,
    required this.child,
    required this.lineHeight,
    this.top = 0,
    this.minLines = 0,
  });

  final Widget child;

  /// Font size × height of the text on the lines.
  final double lineHeight;

  /// Where the first line of text starts.
  final double top;

  /// Draw at least this many lines, even below short text.
  final int minLines;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RulesPainter(lineHeight, top, minLines),
      child: child,
    );
  }
}

class _RulesPainter extends CustomPainter {
  _RulesPainter(this.lineHeight, this.top, this.minLines);

  final double lineHeight;
  final double top;
  final int minLines;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = NoteInk.rule
      ..strokeWidth = 1;
    final drop = lineHeight * .22;
    for (var i = 1; ; i++) {
      final y = top + i * lineHeight - drop;
      if (y > size.height && i > minLines) break;
      if (y > size.height) break;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_RulesPainter oldDelegate) =>
      oldDelegate.lineHeight != lineHeight ||
      oldDelegate.top != top ||
      oldDelegate.minLines != minLines;
}
