import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';

/// A drawn envelope whose flap can open ([flap] 0→1) and whose letter can
/// rise out of it ([rise] 0→1). [seal] sits on the flap's tip while it is
/// closed.
class EnvelopeArt extends StatelessWidget {
  const EnvelopeArt({
    super.key,
    required this.preset,
    this.width = 240,
    this.flap = 0,
    this.rise = 0,
    this.seal,
  });

  final GradientPreset preset;
  final double width;
  final double flap;
  final double rise;
  final Widget? seal;

  static const aspect = .64;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final h = width * aspect;
    final tipY = h * .56 * math.cos(flap * math.pi);
    final sealOpacity = (1 - flap * 2.5).clamp(0.0, 1.0);
    return SizedBox(
      width: width,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _EnvelopePainter(
                colors: preset.colors(Brightness.light),
                accent: preset.accent(Brightness.light),
                flap: flap,
                rise: rise,
                dark: b == Brightness.dark,
              ),
            ),
          ),
          if (seal != null && sealOpacity > 0)
            Positioned(
              left: 0,
              right: 0,
              top: tipY - 26,
              child: Opacity(
                opacity: sealOpacity,
                child: Center(child: seal),
              ),
            ),
        ],
      ),
    );
  }
}

class _EnvelopePainter extends CustomPainter {
  _EnvelopePainter({
    required this.colors,
    required this.accent,
    required this.flap,
    required this.rise,
    required this.dark,
  });

  final List<Color> colors;
  final Color accent;
  final double flap;
  final double rise;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final body = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    final base = Color.lerp(colors[1], Colors.white, .35)!;
    final deep = Color.lerp(colors[1], accent, .22)!;

    // Shadow.
    canvas.drawRRect(
      body.shift(const Offset(0, 10)),
      Paint()
        ..color = Colors.black.withValues(alpha: dark ? .35 : .12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // Back.
    canvas.drawRRect(body, Paint()..color = deep);

    final tipY = h * .56 * math.cos(flap * math.pi);
    final flapPath = Path()
      ..moveTo(0, 0)
      ..lineTo(w / 2, tipY)
      ..lineTo(w, 0)
      ..close();
    final flapPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.lerp(base, accent, .1)!, Color.lerp(base, deep, .5)!],
      ).createShader(Rect.fromLTRB(0, math.min(0, tipY), w, math.max(1, tipY)));

    // An open flap folds behind the letter.
    if (tipY < 0) canvas.drawPath(flapPath, flapPaint);

    // The letter inside.
    if (rise > 0) {
      final top = h * .12 - rise * h * .7;
      final letter = RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .07, top, w * .86, h * .82),
        const Radius.circular(6),
      );
      canvas.drawRRect(letter, Paint()..color = const Color(0xFFFFFBF3));
      final line = Paint()
        ..color = const Color(0x33B0607A)
        ..strokeWidth = 1.4;
      for (var i = 0; i < 4; i++) {
        final y = top + 18 + i * 12.0;
        canvas.drawLine(
          Offset(w * .15, y),
          Offset(w * (i == 3 ? .55 : .85), y),
          line,
        );
      }
    }

    // Front pocket.
    final pocket = Path()
      ..moveTo(0, h * .2)
      ..lineTo(w / 2, h * .62)
      ..lineTo(w, h * .2)
      ..lineTo(w, h - 14)
      ..quadraticBezierTo(w, h, w - 14, h)
      ..lineTo(14, h)
      ..quadraticBezierTo(0, h, 0, h - 14)
      ..close();
    canvas.drawPath(
      pocket,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, Color.lerp(base, colors[2], .6)!],
        ).createShader(Offset.zero & size),
    );
    // Pocket folds.
    final fold = Paint()
      ..color = deep.withValues(alpha: .45)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, h), Offset(w * .42, h * .55), fold);
    canvas.drawLine(Offset(w, h), Offset(w * .58, h * .55), fold);

    // A closed flap lies over the front.
    if (tipY >= 0) {
      canvas.drawShadow(flapPath, Colors.black, 2, false);
      canvas.drawPath(flapPath, flapPaint);
    }
  }

  @override
  bool shouldRepaint(_EnvelopePainter old) =>
      old.flap != flap ||
      old.rise != rise ||
      old.colors != colors ||
      old.dark != dark;
}

/// A round wax seal with a gradient and an emoji or initial.
class WaxSeal extends StatelessWidget {
  const WaxSeal({
    super.key,
    required this.preset,
    required this.label,
    this.size = 52,
    this.glow = 0,
    this.textStyle,
  });

  final GradientPreset preset;
  final String label;
  final double size;

  /// 0–1 extra halo, for pulsing.
  final double glow;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final accent = preset.accent(Brightness.light);
    final deep = Color.lerp(accent, Colors.black, .25)!;
    final light = Color.lerp(accent, Colors.white, .3)!;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-.35, -.4),
          colors: [light, accent, deep],
          stops: const [0, .55, 1],
        ),
        border: Border.all(color: deep.withValues(alpha: .6), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .22),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
          if (glow > 0)
            BoxShadow(
              color: accent.withValues(alpha: .45 * glow),
              blurRadius: 18 + 14 * glow,
              spreadRadius: 4 * glow,
            ),
        ],
      ),
      child: Text(
        label,
        style:
            textStyle ??
            TextStyle(
              fontSize: size * .44,
              color: Colors.white,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
      ),
    );
  }
}
