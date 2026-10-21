import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';

/// Lets the user choose which notifications they want. Returns the new
/// preferences, or null if dismissed.
Future<NotificationPrefs?> showNotificationPrefsSheet(
  BuildContext context,
  NotificationPrefs current,
) {
  return showModalBottomSheet<NotificationPrefs>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _NotificationPrefsSheet(initial: current),
  );
}

class _NotificationPrefsSheet extends StatefulWidget {
  const _NotificationPrefsSheet({required this.initial});

  final NotificationPrefs initial;

  @override
  State<_NotificationPrefsSheet> createState() =>
      _NotificationPrefsSheetState();
}

class _NotificationPrefsSheetState extends State<_NotificationPrefsSheet> {
  late NotificationPrefs _prefs = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader(
              icon: Icons.notifications_none_rounded,
              preset: GradientPreset.ocean,
              title: 'Notifications',
              subtitle:
                  'Choose what you want to hear about. Push notifications are '
                  'coming in an update; your choices are saved for then.',
            ),
            GradientGroup(
              preset: GradientPreset.blush,
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.chat_bubble_outline),
                  title: const Text('New messages and calls'),
                  value: _prefs.messages,
                  onChanged: (v) =>
                      setState(() => _prefs = _prefs.copyWith(messages: v)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.mood),
                  title: const Text('Partner mood updates'),
                  value: _prefs.mood,
                  onChanged: (v) =>
                      setState(() => _prefs = _prefs.copyWith(mood: v)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('Daily question'),
                  value: _prefs.dailyQuestion,
                  onChanged: (v) => setState(
                    () => _prefs = _prefs.copyWith(dailyQuestion: v),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.event_outlined),
                  title: const Text('Birthdays, anniversaries and dates'),
                  value: _prefs.dates,
                  onChanged: (v) =>
                      setState(() => _prefs = _prefs.copyWith(dates: v)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GradientGroup(
              preset: GradientPreset.night,
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.bedtime_outlined),
                  title: const Text('Quiet hours'),
                  subtitle: const Text('Silence notifications 10 pm – 7 am'),
                  value: _prefs.quietHours,
                  onChanged: (v) =>
                      setState(() => _prefs = _prefs.copyWith(quietHours: v)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, _prefs),
              style: pillButtonStyle(context),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
