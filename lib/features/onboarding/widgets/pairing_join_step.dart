import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:couple_app/core/utils/upper_case_formatter.dart';
import 'package:couple_app/features/couple/models/invite.dart';
import 'package:couple_app/features/onboarding/widgets/busy_button_label.dart';
import 'package:couple_app/features/onboarding/widgets/onboarding_progress.dart';
import 'package:couple_app/features/onboarding/widgets/pairing_error_text.dart';

/// Pairing step for joining a partner: type or scan their invite code.
class PairingJoinStep extends StatelessWidget {
  const PairingJoinStep({
    super.key,
    required this.code,
    required this.busy,
    required this.error,
    required this.onSubmit,
    required this.onScan,
  });

  final TextEditingController code;
  final bool busy;
  final String? error;
  final VoidCallback onSubmit;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingProgress(step: OnboardingStep.space),
        const SizedBox(height: 28),
        Text(
          'Enter the invite code',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Your partner can find it on their invite screen.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          maxLength: InviteCode.length,
          style: const TextStyle(
            fontSize: 26,
            letterSpacing: 10,
            fontWeight: FontWeight.w700,
          ),
          decoration: const InputDecoration(
            hintText: 'HJK456',
            counterText: '',
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
            UpperCaseFormatter(),
          ],
          onSubmitted: (_) => onSubmit(),
        ),
        PairingErrorText(error: error),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy ? null : onSubmit,
          child: BusyButtonLabel(busy: busy, label: 'Continue'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy ? null : onScan,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan their QR code'),
        ),
      ],
    );
  }
}
