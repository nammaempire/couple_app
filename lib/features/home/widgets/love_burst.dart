import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:couple_app/core/navigation/app_navigator.dart';
import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/avatar/widgets/avatar_view.dart';
import 'package:couple_app/features/home/models/love_tap.dart';

/// The full-screen love-tap animation: one big avatar pulling the tap's
/// face (or the tap's emoji, without an avatar) pops up in the middle,
/// small emojis burst out from it to fill the screen and drift up, over a
/// soft glow in the tap's colour. Plays for [duration], above every screen,
/// and never blocks touches.
///
/// The sender sees their own avatar when they tap; the partner sees the
/// sender's avatar when it arrives.
abstract final class LoveBurst {
  static const duration = Duration(milliseconds: 2300);

  static OverlayEntry? _entry;

  /// Plays the burst for [tap]. [overlay] defaults to the app's root
  /// overlay. A new burst replaces one still playing.
  static void play(LoveTap tap, {AvatarConfig? avatar, OverlayState? overlay}) {
    final target = overlay ?? appNavigatorKey.currentState?.overlay;
    if (target == null || !target.mounted) return;
    if (MediaQuery.maybeDisableAnimationsOf(target.context) ?? false) return;

    _entry?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => LoveBurstView(
        key: UniqueKey(),
        tap: tap,
        avatar: avatar,
        onDone: () {
          if (_entry != entry) return;
          entry.remove();
          _entry = null;
        },
      ),
    );
    _entry = entry;
    target.insert(entry);
  }
}

/// Who is pulling which face right now, by uid: the Home header avatars
/// copy the love tap that was just sent or received for a moment.
abstract final class AvatarReactions {
  static const hold = Duration(milliseconds: 2600);

  static final faces = ValueNotifier<Map<String, AvatarExpression>>(const {});
  static final _timers = <String, Timer>{};

  static void react(String uid, AvatarExpression face) {
    _timers.remove(uid)?.cancel();
    faces.value = {...faces.value, uid: face};
    _timers[uid] = Timer(hold, () {
      _timers.remove(uid);
      faces.value = {...faces.value}..remove(uid);
    });
  }
}

class _Particle {
  const _Particle(
    this.emoji,
    this.size,
    this.target,
    this.drift,
    this.spin,
    this.delay,
  );

  final String emoji;
  final double size;

  /// Where it lands after bursting out (its centre).
  final Offset target;

  /// Where it ends after drifting.
  final Offset drift;
  final double spin;

  /// Start delay, as a fraction of the animation.
  final double delay;
}

/// One play of the burst; calls [onDone] when finished.
class LoveBurstView extends StatefulWidget {
  const LoveBurstView({
    super.key,
    required this.tap,
    required this.onDone,
    this.avatar,
  });

  final LoveTap tap;
  final AvatarConfig? avatar;
  final VoidCallback onDone;

  @override
  State<LoveBurstView> createState() => _LoveBurstViewState();
}

class _LoveBurstViewState extends State<LoveBurstView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: LoveBurst.duration,
  );
  final _random = Random();
  List<_Particle>? _particles;
  Size? _laidOutFor;

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Spreads the small emojis over a grid, one per cell, so they fill the
  /// whole screen evenly.
  List<_Particle> _layout(Size size) {
    const cols = 6;
    final rows = max(8, (cols * size.height / size.width).round());
    final cw = size.width / cols;
    final ch = size.height / rows;
    final set = widget.tap.particles;
    return [
      for (var r = 0; r < rows; r++)
        for (var c = 0; c < cols; c++)
          () {
            final s = 22 + _random.nextDouble() * 22;
            final target = Offset(
              c * cw + _random.nextDouble() * cw,
              r * ch + _random.nextDouble() * ch,
            );
            return _Particle(
              set[_random.nextInt(set.length)],
              s,
              target,
              target +
                  Offset(
                    (_random.nextDouble() - .5) * 50,
                    -30 - _random.nextDouble() * 60,
                  ),
              (_random.nextDouble() - .5) * 1.8,
              _random.nextDouble() * .04,
            );
          }(),
    ];
  }

  /// Pops in fast, overshoots, settles and grows slowly, then swells away.
  static double _bigScale(double t) {
    if (t < .1) return .3 + (t / .1) * .82;
    if (t < .18) return 1.12 - ((t - .1) / .08) * .12;
    if (t < .7) return 1 + (t - .18) * .08;
    return 1.04 + (t - .7) * .7;
  }

  static double _fade(double t) =>
      t < .7 ? 1 : (1 - (t - .7) / .3).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (_particles == null || _laidOutFor != size) {
      _particles = _layout(size);
      _laidOutFor = size;
    }
    final particles = _particles!;
    final tap = widget.tap;
    final avatar = widget.avatar;
    final bigSize = min(size.width, size.height) * (avatar != null ? .9 : .75);

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final fade = _fade(t);
          return Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: fade,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [tap.tint, tap.tint.withAlpha(0)],
                      radius: .8,
                    ),
                  ),
                ),
              ),
              CustomPaint(
                painter: _ParticlePainter(
                  particles: particles,
                  t: t,
                  center: size.center(Offset.zero),
                ),
              ),
              Center(
                child: Opacity(
                  opacity: fade,
                  child: Transform.scale(
                    scale: _bigScale(t),
                    child: SizedBox.square(
                      dimension: bigSize,
                      child: avatar != null
                          ? AvatarView(
                              config: avatar,
                              expression: tap.expression,
                              size: bigSize,
                              showBackground: false,
                            )
                          : FittedBox(
                              child: Text(
                                tap.emoji,
                                style: const TextStyle(fontSize: 200),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Paints the small emojis. Each emoji is laid out once and reused every
/// frame, so dozens of them animate smoothly.
class _ParticlePainter extends CustomPainter {
  _ParticlePainter({
    required this.particles,
    required this.t,
    required this.center,
  });

  final List<_Particle> particles;
  final double t;
  final Offset center;

  static final _cache = <(String, int), TextPainter>{};

  static TextPainter _glyph(String emoji, double size) {
    // Sizes rounded to whole pixels keep the cache small.
    final key = (emoji, size.round());
    return _cache.putIfAbsent(key, () {
      if (_cache.length > 200) _cache.clear();
      return TextPainter(
        text: TextSpan(
          text: emoji,
          style: TextStyle(fontSize: key.$2.toDouble()),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final lt = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      final Offset at;
      final double scale;
      final double opacity;
      if (lt < .16) {
        // Bursting out from the middle.
        final k = Curves.easeOutCubic.transform(lt / .16);
        at = Offset.lerp(center, p.target, k)!;
        scale = .2 + .95 * k;
        opacity = 1;
      } else {
        // Drifting up and shrinking, fading at the end.
        final k = (lt - .16) / .84;
        at = Offset.lerp(p.target, p.drift, k)!;
        scale = 1.15 - .35 * k;
        opacity = lt < .7 ? 1 : (1 - (lt - .7) / .3).clamp(0.0, 1.0);
      }
      if (opacity <= 0) continue;
      final glyph = _glyph(p.emoji, p.size);
      canvas
        ..save()
        ..translate(at.dx, at.dy)
        ..rotate(p.spin * lt)
        ..scale(scale);
      final offset = Offset(-glyph.width / 2, -glyph.height / 2);
      if (opacity < 1) {
        canvas.saveLayer(
          offset & glyph.size,
          Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
        );
        glyph.paint(canvas, offset);
        canvas.restore();
      } else {
        glyph.paint(canvas, offset);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) =>
      old.t != t || old.particles != particles;
}
