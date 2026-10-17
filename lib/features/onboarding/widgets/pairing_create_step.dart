import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/widgets/photo_picker_avatar.dart';
import 'package:couple_app/features/onboarding/widgets/busy_button_label.dart';
import 'package:couple_app/features/onboarding/widgets/onboarding_progress.dart';
import 'package:couple_app/features/onboarding/widgets/pairing_error_text.dart';

/// Pairing step for creating a new couple space: photo, name and start date.
class PairingCreateStep extends StatelessWidget {
  const PairingCreateStep({
    super.key,
    required this.couplePhoto,
    required this.onPhotoPicked,
    required this.coupleName,
    required this.startDate,
    required this.onPickStartDate,
    required this.busy,
    required this.error,
    required this.onCreate,
  });

  final File? couplePhoto;
  final ValueChanged<File> onPhotoPicked;
  final TextEditingController coupleName;
  final DateTime? startDate;
  final VoidCallback onPickStartDate;
  final bool busy;
  final String? error;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingProgress(step: OnboardingStep.space),
        const SizedBox(height: 28),
        Center(
          child: PhotoPickerAvatar(
            file: couplePhoto,
            icon: Icons.favorite_outline,
            label: 'Add a couple photo',
            onPicked: onPhotoPicked,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'A couple photo (optional)',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: coupleName,
          textCapitalization: TextCapitalization.words,
          maxLength: 24,
          decoration: const InputDecoration(
            labelText: 'Name your space (optional)',
            hintText: 'e.g. Sam & Alex',
            prefixIcon: Icon(Icons.edit_outlined),
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: busy ? null : onPickStartDate,
          borderRadius: BorderRadius.circular(24),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'When did you two start?',
              prefixIcon: Icon(Icons.calendar_today_outlined),
            ),
            child: Text(
              startDate == null
                  ? 'Pick your date (optional)'
                  : DateFormat.yMMMMd().format(startDate!),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: startDate == null
                    ? theme.colorScheme.onSurfaceVariant
                    : null,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(
            'Starts your days-together counter. You can change it later.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        PairingErrorText(error: error),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: busy ? null : onCreate,
          child: BusyButtonLabel(busy: busy, label: 'Create and get invite'),
        ),
      ],
    );
  }
}
