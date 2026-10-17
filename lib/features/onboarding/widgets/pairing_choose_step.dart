import 'package:flutter/material.dart';

import 'package:couple_app/features/onboarding/widgets/how_connecting_works.dart';
import 'package:couple_app/features/onboarding/widgets/onboarding_progress.dart';
import 'package:couple_app/features/onboarding/widgets/pairing_choice_card.dart';
import 'package:couple_app/features/onboarding/widgets/pairing_notice.dart';

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingProgress(step: OnboardingStep.space),
        if (notice != null) ...[
          const SizedBox(height: 16),
          PairingNotice(text: notice!),
        ],
        const SizedBox(height: 28),
        Text(
          'Connect with your partner',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'One of you creates your shared space. The other joins with the invite.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        PairingChoiceCard(
          icon: Icons.favorite_outline,
          title: 'Create our space',
          body: 'Set it up and get an invite to send your partner.',
          onTap: onCreate,
        ),
        const SizedBox(height: 12),
        PairingChoiceCard(
          icon: Icons.qr_code_scanner,
          title: 'I have an invite',
          body: 'Enter or scan the code your partner shared.',
          onTap: onJoin,
        ),
        const SizedBox(height: 24),
        const HowConnectingWorks(),
      ],
    );
  }
}
