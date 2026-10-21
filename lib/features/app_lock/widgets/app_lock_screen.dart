import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/avatar/widgets/profile_avatar.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';

/// Full-screen "Us is locked" page with an Unlock button.
///
/// Drawn above the navigator, so it uses no tooltips or other widgets that
/// need an [Overlay].
class AppLockScreen extends StatelessWidget {
  const AppLockScreen({
    super.key,
    this.me,
    this.partner,
    required this.authenticating,
    required this.failed,
    required this.onUnlock,
  });

  /// The couple, for their pictures. Without both, the app's heart shows
  /// instead.
  final AppUser? me;
  final AppUser? partner;

  /// The system prompt is up; the button waits.
  final bool authenticating;

  /// The last attempt failed or was cancelled.
  final bool failed;

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = this.me;
    final partner = this.partner;
    const preset = GradientPreset.night;
    const fg = Color(0xFFFFF4F6);
    final muted = fg.withValues(alpha: .8);
    const gold = Color(0xFFFFE08A);

    Widget ringed(AppUser user) => Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [gold, Color(0xFFFFB0DA), Color(0xFFCDB8FF)],
        ),
        boxShadow: [
          BoxShadow(color: gold.withValues(alpha: .25), blurRadius: 18),
        ],
      ),
      child: ProfileAvatar(user: user, size: 64),
    );

    return Material(
      color: preset.dark.first,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(
            child: AnimatedGradientBackground(
              preset: preset,
              duration: Duration(seconds: 16),
            ),
          ),
          const Positioned.fill(
            child: FloatingHearts(
              style: ParticleStyle.stars,
              count: 26,
              color: gold,
              opacity: .7,
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (me != null && partner != null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ringed(me),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Icon(
                                Icons.favorite_rounded,
                                size: 26,
                                color: Color(0xFFFFB0DA),
                              ),
                            ),
                            ringed(partner),
                          ],
                        )
                      else
                        const Center(
                          child: Icon(
                            Icons.favorite_rounded,
                            size: 56,
                            color: Color(0xFFFFB0DA),
                          ),
                        ),
                      const SizedBox(height: 28),
                      GlassPanel(
                        dark: true,
                        radius: 28,
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Icon(
                              Icons.lock_rounded,
                              size: 26,
                              color: gold,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Us is locked',
                              textAlign: TextAlign.center,
                              style: romanceSerif(theme.textTheme.headlineSmall)
                                  .copyWith(
                                    color: fg,
                                    fontWeight: FontWeight.w700,
                                    fontStyle: FontStyle.italic,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Use your fingerprint, face or phone PIN to open it.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: muted,
                                height: 1.4,
                              ),
                            ),
                            if (failed) ...[
                              const SizedBox(height: 14),
                              Text(
                                'That didn\'t work. Try again.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: const Color(0xFFFFB4AB),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 22),
                            FilledButton.icon(
                              onPressed: authenticating ? null : onUnlock,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(54),
                                backgroundColor: gold,
                                foregroundColor: const Color(0xFF2A1F4D),
                                disabledBackgroundColor: Colors.white
                                    .withValues(alpha: .16),
                                disabledForegroundColor: fg.withValues(
                                  alpha: .6,
                                ),
                                shape: const StadiumBorder(),
                                textStyle: theme.textTheme.labelLarge?.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              icon: const Icon(Icons.fingerprint),
                              label: const Text('Unlock'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
