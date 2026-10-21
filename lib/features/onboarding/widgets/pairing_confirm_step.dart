import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/couple/models/invite.dart';
import 'package:couple_app/features/onboarding/widgets/busy_button_label.dart';
import 'package:couple_app/features/onboarding/widgets/check_bullet.dart';
import 'package:couple_app/features/onboarding/widgets/onboarding_progress.dart';
import 'package:couple_app/features/onboarding/widgets/pairing_error_text.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';

/// Pairing step that shows who sent [invite] and asks to accept it.
class PairingConfirmStep extends StatelessWidget {
  const PairingConfirmStep({
    super.key,
    required this.invite,
    required this.busy,
    required this.error,
    required this.onAccept,
    required this.onUseAnotherCode,
  });

  final Invite invite;
  final bool busy;
  final String? error;
  final VoidCallback onAccept;
  final VoidCallback onUseAnotherCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final dark = b == Brightness.dark;
    const preset = GradientPreset.blush;
    final photo = invite.inviterPhotoUrl;
    final initial = invite.inviterName.isEmpty
        ? '?'
        : invite.inviterName.characters.first.toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingProgress(step: OnboardingStep.space),
        const SizedBox(height: 20),
        AnimatedGradientCard(
          preset: GradientPreset.blush,
          radius: 30,
          padding: EdgeInsets.zero,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(
                child: FloatingHearts(
                  count: 12,
                  color: Colors.white,
                  opacity: dark ? .25 : .75,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
                child: Column(
                  children: [
                    GlowRing(
                      child: CircleAvatar(
                        radius: 46,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        backgroundImage: photo == null
                            ? null
                            : CachedNetworkImageProvider(photo),
                        child: photo == null
                            ? Text(
                                initial,
                                style:
                                    romanceSerif(
                                      theme.textTheme.headlineMedium,
                                    ).copyWith(
                                      color:
                                          theme.colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${invite.inviterName} invited you',
                      textAlign: TextAlign.center,
                      style: romanceSerif(theme.textTheme.headlineSmall)
                          .copyWith(
                            fontWeight: FontWeight.w700,
                            fontStyle: FontStyle.italic,
                            color: preset.foreground(b),
                          ),
                    ),
                    if (invite.coupleName != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'to join “${invite.coupleName}”',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: preset.foregroundMuted(b),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassPanel(
          dark: dark,
          radius: 22,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'When you accept',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              CheckBullet(
                'You and ${invite.inviterName} share one private space.',
              ),
              const CheckBullet(
                'Only the two of you can see what is shared in it.',
              ),
              const CheckBullet(
                'The invite closes, so nobody else can join with this code.',
              ),
            ],
          ),
        ),
        PairingErrorText(error: error),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: busy ? null : onAccept,
          style: pillButtonStyle(context),
          child: BusyButtonLabel(busy: busy, label: 'Accept and connect'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: busy ? null : onUseAnotherCode,
          child: const Text('Not them? Use another code'),
        ),
      ],
    );
  }
}
