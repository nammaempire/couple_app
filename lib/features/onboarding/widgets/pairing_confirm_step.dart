import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:couple_app/features/couple/models/invite.dart';
import 'package:couple_app/features/onboarding/widgets/busy_button_label.dart';
import 'package:couple_app/features/onboarding/widgets/check_bullet.dart';
import 'package:couple_app/features/onboarding/widgets/onboarding_progress.dart';
import 'package:couple_app/features/onboarding/widgets/pairing_error_text.dart';

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
    final photo = invite.inviterPhotoUrl;
    final initial = invite.inviterName.isEmpty
        ? '?'
        : invite.inviterName.characters.first.toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingProgress(step: OnboardingStep.space),
        const SizedBox(height: 32),
        Center(
          child: CircleAvatar(
            radius: 48,
            backgroundColor: theme.colorScheme.primaryContainer,
            backgroundImage: photo == null
                ? null
                : CachedNetworkImageProvider(photo),
            child: photo == null
                ? Text(
                    initial,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '${invite.inviterName} invited you',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (invite.coupleName != null) ...[
          const SizedBox(height: 4),
          Text(
            'to join “${invite.coupleName}”',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: .5,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'When you accept',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
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
