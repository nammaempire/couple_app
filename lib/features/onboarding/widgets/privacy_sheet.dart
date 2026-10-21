import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';

/// Plain-language summary of who can see what. Returns true when the user
/// taps "Got it".
Future<bool?> showPrivacySheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: staggered([
              const SheetHeader(
                icon: Icons.shield_outlined,
                preset: GradientPreset.mint,
                title: 'Your privacy',
              ),
              const _PrivacyPoint(
                icon: Icons.lock_outline,
                preset: GradientPreset.blush,
                title: 'Only the two of you',
                body:
                    'Messages, photos, calls, moods and answers are visible '
                    'only to you and your partner.',
              ),
              const _PrivacyPoint(
                icon: Icons.visibility_off_outlined,
                preset: GradientPreset.lavender,
                title: 'Answers stay hidden',
                body:
                    'You see each other\'s daily answers only after you have '
                    'both replied.',
              ),
              const _PrivacyPoint(
                icon: Icons.person_outline,
                preset: GradientPreset.peach,
                title: 'One partner at a time',
                body:
                    'Your space holds exactly two people. Nobody else can '
                    'join it.',
              ),
              const _PrivacyPoint(
                icon: Icons.location_off_outlined,
                preset: GradientPreset.mint,
                title: 'No location tracking',
                body: 'The app does not collect your location.',
              ),
              const SizedBox(height: 6),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext, true),
                style: pillButtonStyle(
                  sheetContext,
                  preset: GradientPreset.mint,
                ),
                child: const Text('Got it'),
              ),
            ]),
          ),
        ),
      );
    },
  );
}

class _PrivacyPoint extends StatelessWidget {
  const _PrivacyPoint({
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
    final b = theme.brightness;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedGradientCard(
        preset: preset,
        radius: 20,
        shadow: false,
        sheen: false,
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(icon: icon, preset: preset, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: preset.foreground(b),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: preset.foregroundMuted(b),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
