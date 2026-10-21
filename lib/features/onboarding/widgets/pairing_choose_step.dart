import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/onboarding/widgets/how_connecting_works.dart';
import 'package:couple_app/features/onboarding/widgets/onboarding_progress.dart';
import 'package:couple_app/features/onboarding/widgets/pairing_choice_card.dart';
import 'package:couple_app/features/onboarding/widgets/pairing_notice.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';

/// First pairing step: choose between creating a space and joining one.
class PairingChooseStep extends StatelessWidget {
  const PairingChooseStep({
    super.key,
    required this.notice,
    required this.onCreate,
    required this.onJoin,
  });

  /// Optional message shown at the top, e.g. when a previous space is gone.
  final String? notice;
  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: staggered([
        const OnboardingProgress(step: OnboardingStep.space),
        if (notice != null) ...[
          const SizedBox(height: 16),
          PairingNotice(text: notice!),
        ],
        const SizedBox(height: 24),
        const Center(child: _TwoHearts()),
        const SizedBox(height: 16),
        Text(
          'Connect with your partner',
          textAlign: TextAlign.center,
          style: romanceSerif(theme.textTheme.headlineMedium).copyWith(
            fontWeight: FontWeight.w700,
            fontStyle: FontStyle.italic,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'One of you creates your shared space. The other joins with the invite.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        PairingChoiceCard(
          icon: Icons.favorite_outline,
          preset: GradientPreset.blush,
          title: 'Create our space',
          body: 'Set it up and get an invite to send your partner.',
          onTap: onCreate,
        ),
        const SizedBox(height: 14),
        PairingChoiceCard(
          icon: Icons.qr_code_scanner,
          preset: GradientPreset.ocean,
          title: 'I have an invite',
          body: 'Enter or scan the code your partner shared.',
          onTap: onJoin,
        ),
        const SizedBox(height: 20),
        GlassPanel(
          dark: dark,
          radius: 22,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: const Material(
            type: MaterialType.transparency,
            child: HowConnectingWorks(),
          ),
        ),
      ]),
    );
  }
}

/// Two linked rings with a heart between them: the moment two people meet.
class _TwoHearts extends StatelessWidget {
  const _TwoHearts();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 150,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 0,
            child: GlowBadge(
              preset: GradientPreset.blush,
              icon: Icons.person_rounded,
              size: 64,
            ),
          ),
          Positioned(
            right: 0,
            child: GlowBadge(
              preset: GradientPreset.lavender,
              icon: Icons.person_rounded,
              size: 64,
            ),
          ),
          GlowBadge(
            preset: GradientPreset.festive,
            icon: Icons.favorite_rounded,
            size: 38,
          ),
        ],
      ),
    );
  }
}
