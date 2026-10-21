import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/avatar/widgets/profile_avatar.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';

/// Top of the Us tab: both partners' pictures joined by a heart, the
/// space's name in serif and how long they've been together, on a drifting
/// blush gradient with hearts floating behind.
class UsHeroCard extends StatelessWidget {
  const UsHeroCard({
    super.key,
    required this.title,
    required this.myName,
    required this.partnerName,
    this.me,
    this.partner,
    this.startDate,
  });

  final String title;
  final String myName;
  final String partnerName;
  final AppUser? me;
  final AppUser? partner;
  final DateTime? startDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    const preset = GradientPreset.blush;
    final start = startDate;
    final days = start == null
        ? null
        : DateTime.now().difference(start).inDays.clamp(0, 1 << 30);

    return AnimatedGradientCard(
      preset: preset,
      radius: 28,
      padding: EdgeInsets.zero,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: FloatingHearts(
              count: 10,
              color: Colors.white,
              opacity: b == Brightness.dark ? .22 : .7,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Ringed(
                      child: ProfileAvatar(
                        user: me,
                        size: 60,
                        fallbackName: myName,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: GlowBadge(
                        preset: preset,
                        size: 34,
                        icon: Icons.favorite_rounded,
                      ),
                    ),
                    _Ringed(
                      child: ProfileAvatar(
                        user: partner,
                        size: 60,
                        fallbackName: partnerName,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: romanceSerif(theme.textTheme.headlineSmall).copyWith(
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.italic,
                    color: preset.foreground(b),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  start == null
                      ? 'Set the day you started to count your days'
                      : 'Together since ${DateFormat.yMMMMd().format(start)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: preset.foregroundMuted(b),
                  ),
                ),
                if (days != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: preset.isDarkIn(b) ? .12 : .65,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${NumberFormat.decimalPattern().format(days)} '
                      '${days == 1 ? 'day' : 'days'} of us',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: preset.foreground(b),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Ringed extends StatelessWidget {
  const _Ringed({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: dark ? .25 : .9),
      ),
      child: child,
    );
  }
}
