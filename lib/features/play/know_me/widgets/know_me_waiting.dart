import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/entrance_animation.dart';

/// A calm, centred message while the partner takes their turn (or, with
/// [action], while something is ready for me to do).
class KnowMeWaiting extends StatelessWidget {
  const KnowMeWaiting({
    super.key,
    required this.emoji,
    required this.title,
    required this.message,
    this.action,
  });

  final String emoji;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.85, end: 1),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Bobbing(
                amplitude: 5,
                child: Container(
                  width: 104,
                  height: 104,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: dark ? .12 : .8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: dark ? .2 : .9),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: .18),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 48)),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[const SizedBox(height: 24), action!],
            ],
          ),
        ),
      ),
    );
  }
}
