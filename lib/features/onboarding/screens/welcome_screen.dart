import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';

/// First screen for signed-out users: the emotional promise, then sign-up.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.onGetStarted,
    required this.onSignIn,
  });

  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    var i = 0;
    Widget enter(Widget child) => EntranceAnimation(index: i++, child: child);

    return RomanceBackdrop(
      preset: GradientPreset.blush,
      hearts: true,
      heartCount: 16,
      strength: .85,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          // Scrolls on short screens; spacers spread content on tall ones.
          child: LayoutBuilder(
            builder: (context, viewport) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: viewport.maxHeight),
                child: IntrinsicHeight(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Spacer(flex: 2),
                            enter(const Center(child: _HeartsMark())),
                            const SizedBox(height: 26),
                            enter(
                              Text(
                                'Everything that belongs to us, in one private place.',
                                textAlign: TextAlign.center,
                                style:
                                    romanceSerif(
                                      theme.textTheme.headlineMedium,
                                    ).copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontStyle: FontStyle.italic,
                                      height: 1.2,
                                      color: dark
                                          ? scheme.onSurface
                                          : const Color(0xFF3B1424),
                                    ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            enter(
                              Text(
                                'A space made for exactly two people — to talk, '
                                'remember and plan your life together.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.45,
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
                            enter(
                              GlassPanel(
                                dark: dark,
                                radius: 26,
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  16,
                                  16,
                                  4,
                                ),
                                child: const Column(
                                  children: [
                                    _Promise(
                                      icon: Icons.lock_outline_rounded,
                                      preset: GradientPreset.blush,
                                      title: 'Just the two of you',
                                      body:
                                          'Only you and your partner can see what you share.',
                                    ),
                                    _Promise(
                                      icon: Icons.chat_bubble_outline_rounded,
                                      preset: GradientPreset.lavender,
                                      title: 'Talk, call, send photos',
                                      body:
                                          'A private chat with voice and video calls.',
                                    ),
                                    _Promise(
                                      icon: Icons.auto_awesome_outlined,
                                      preset: GradientPreset.gold,
                                      title: 'Stay close every day',
                                      body:
                                          'Moods, a daily question and your days-together count.',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Spacer(flex: 3),
                            const SizedBox(height: 24),
                            enter(
                              FilledButton(
                                onPressed: onGetStarted,
                                style: pillButtonStyle(context),
                                child: const Text('Get started'),
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextButton(
                              onPressed: onSignIn,
                              style: TextButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                foregroundColor: dark
                                    ? scheme.primary
                                    : GradientPreset.blush.ink,
                                textStyle: theme.textTheme.labelLarge?.copyWith(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: const Text('I already have an account'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two overlapping hearts on a glowing gradient badge, gently bobbing.
class _HeartsMark extends StatelessWidget {
  const _HeartsMark();

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final dark = b == Brightness.dark;
    const preset = GradientPreset.blush;
    final ink = dark ? preset.accent(b) : preset.ink;
    return Bobbing(
      amplitude: 5,
      child: GlowBadge(
        size: 112,
        preset: preset,
        child: SizedBox(
          width: 80,
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.translate(
                offset: const Offset(-12, 3),
                child: Icon(
                  Icons.favorite_rounded,
                  size: 48,
                  color: ink.withValues(alpha: .35),
                ),
              ),
              Transform.translate(
                offset: const Offset(12, -3),
                child: Icon(Icons.favorite_rounded, size: 48, color: ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Promise extends StatelessWidget {
  const _Promise({
    required this.icon,
    required this.preset,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final GradientPreset preset;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: icon, preset: preset, size: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
