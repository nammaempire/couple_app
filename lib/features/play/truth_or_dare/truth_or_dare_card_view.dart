import 'dart:math';

import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/music/widgets/on_gradient_theme.dart';
import 'package:couple_app/features/play/truth_or_dare/truth_or_dare_cards.dart';

/// The big card in the middle of the table. Shows its back while nothing
/// is drawn, and flips over (a 3D turn) when a new card arrives.
class TruthOrDareCardView extends StatelessWidget {
  const TruthOrDareCardView({super.key, required this.card});

  /// The drawn card, or null to show the back.
  final TruthOrDareCard? card;

  @override
  Widget build(BuildContext context) {
    final card = this.card;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final angle = (1 - animation.value) * pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(angle),
            child: Opacity(
              opacity: animation.value.clamp(0.0, 1.0),
              child: child,
            ),
          );
        },
      ),
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.center, children: [?current]),
      child: card == null
          ? const _CardBack(key: ValueKey('back'))
          : _CardFront(key: ValueKey(card.id), card: card),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.preset, required this.child, this.particles});

  final GradientPreset preset;
  final ParticleStyle? particles;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final particles = this.particles;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340, minHeight: 200),
      child: SizedBox(
        width: double.infinity,
        child: AnimatedGradientCard(
          preset: preset,
          radius: 28,
          padding: EdgeInsets.zero,
          border: Border.all(
            color: Colors.white.withValues(
              alpha: preset.isDarkIn(b) ? .16 : .75,
            ),
            width: 1.5,
          ),
          child: Stack(
            children: [
              if (particles != null)
                Positioned.fill(
                  child: FloatingHearts(
                    style: particles,
                    count: particles == ParticleStyle.stars ? 24 : 9,
                    opacity: particles == ParticleStyle.stars ? .8 : .45,
                    color: particles == ParticleStyle.stars
                        ? const Color(0xFFFFF1C2)
                        : Colors.white,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card back's and faces' gradients.
abstract final class TruthOrDareLook {
  static const back = GradientPreset.night;
  static const truth = GradientPreset.ocean;
  static const dare = GradientPreset.festive;
}

class _CardBack extends StatelessWidget {
  const _CardBack({super.key});

  @override
  Widget build(BuildContext context) {
    const preset = TruthOrDareLook.back;
    final b = Theme.of(context).brightness;
    return _CardShell(
      preset: preset,
      particles: ParticleStyle.stars,
      child: SizedBox(
        height: 160,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Bobbing(
              amplitude: 4,
              tilt: .05,
              child: Text('💌', style: TextStyle(fontSize: 52)),
            ),
            const SizedBox(height: 8),
            Text(
              'Truth or dare?',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: preset.foreground(b),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardFront extends StatelessWidget {
  const _CardFront({super.key, required this.card});

  final TruthOrDareCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final isTruth = card.kind == TruthOrDareKind.truth;
    final preset = isTruth ? TruthOrDareLook.truth : TruthOrDareLook.dare;
    final fg = preset.foreground(b);
    final accent = OnGradientTheme.ink(preset, b);
    return _CardShell(
      preset: preset,
      particles: isTruth ? null : ParticleStyle.hearts,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(
                    alpha: preset.isDarkIn(b) ? .14 : .7,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  isTruth ? '💬' : '✨',
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  card.kind.label.toUpperCase(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: accent,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            card.text,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}
