import 'dart:math';

import 'package:flutter/material.dart';

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
  const _CardShell({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340, minHeight: 200),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _CardShell(
      color: scheme.primary,
      child: SizedBox(
        height: 160,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('💌', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 8),
            Text(
              'Truth or dare?',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: scheme.onPrimary,
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
    final scheme = theme.colorScheme;
    final isTruth = card.kind == TruthOrDareKind.truth;
    final bg = isTruth ? scheme.primaryContainer : scheme.tertiaryContainer;
    final fg = isTruth ? scheme.onPrimaryContainer : scheme.onTertiaryContainer;
    return _CardShell(
      color: bg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(isTruth ? '💬' : '✨', style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text(
                card.kind.label.toUpperCase(),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: fg,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            card.text,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}
