import 'package:flutter/material.dart';

/// Plain-language summary of who can see what. Returns true when the user
/// taps "Got it".
Future<bool?> showPrivacySheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Your privacy', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              const _PrivacyPoint(
                icon: Icons.lock_outline,
                title: 'Only the two of you',
                body:
                    'Messages, photos, calls, moods and answers are visible '
                    'only to you and your partner.',
              ),
              const _PrivacyPoint(
                icon: Icons.visibility_off_outlined,
                title: 'Answers stay hidden',
                body:
                    'You see each other\'s daily answers only after you have '
                    'both replied.',
              ),
              const _PrivacyPoint(
                icon: Icons.person_outline,
                title: 'One partner at a time',
                body:
                    'Your space holds exactly two people. Nobody else can '
                    'join it.',
              ),
              const _PrivacyPoint(
                icon: Icons.location_off_outlined,
                title: 'No location tracking',
                body: 'The app does not collect your location.',
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext, true),
                child: const Text('Got it'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _PrivacyPoint extends StatelessWidget {
  const _PrivacyPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
