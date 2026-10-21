import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/app_lock/app_lock_controller.dart';
import 'package:couple_app/features/app_lock/data/app_lock_settings.dart';
import 'package:couple_app/features/app_lock/providers/app_lock_providers.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';
import 'package:couple_app/features/us/widgets/settings_section_header.dart';

/// Shown under the switch when the phone has nothing to unlock with.
const appLockUnavailableText =
    'Set up a fingerprint, face or screen lock in your phone\'s settings '
    'first';

/// Turns the app lock on or off and picks how soon it locks. Changes apply
/// right away.
Future<void> showAppLockSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _AppLockSheet(),
  );
}

class _AppLockSheet extends ConsumerStatefulWidget {
  const _AppLockSheet();

  @override
  ConsumerState<_AppLockSheet> createState() => _AppLockSheetState();
}

class _AppLockSheetState extends ConsumerState<_AppLockSheet> {
  /// Null while checking.
  bool? _canAuthenticate;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _checkDevice();
  }

  Future<void> _checkDevice() async {
    final can = await ref.read(biometricAuthProvider).canAuthenticate();
    if (mounted) setState(() => _canAuthenticate = can);
  }

  Future<void> _setEnabled(bool enabled) async {
    final controller = ref.read(appLockControllerProvider.notifier);
    setState(() {
      _busy = true;
      _message = null;
    });
    final ok = await controller.setEnabled(enabled);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _message = 'Couldn\'t confirm it\'s you, so app lock is off.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lock = ref.watch(appLockControllerProvider);
    final unavailable = _canAuthenticate == false;
    // Always allowed to turn it off, even if the phone's lock was removed.
    final canToggle = !_busy && (lock.enabled || _canAuthenticate == true);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader(
              icon: Icons.lock_outline_rounded,
              preset: GradientPreset.lavender,
              title: 'App lock',
              subtitle:
                  'Ask for your fingerprint, face or phone PIN to open Us. '
                  'This is set for this phone only.',
            ),
            GradientGroup(
              preset: GradientPreset.night,
              animate: false,
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.lock_outline),
                  title: const Text('App lock'),
                  subtitle: Text(
                    unavailable && !lock.enabled
                        ? appLockUnavailableText
                        : 'Fingerprint, face or phone PIN',
                  ),
                  value: lock.enabled,
                  onChanged: canToggle ? _setEnabled : null,
                ),
              ],
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
                child: Text(
                  _message!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const SettingsSectionHeader(label: 'Lock after'),
            GradientGroup(
              preset: GradientPreset.lavender,
              animate: false,
              children: [
                RadioGroup<LockDelay>(
                  groupValue: lock.delay,
                  onChanged: (delay) {
                    if (delay == null || !lock.enabled) return;
                    ref
                        .read(appLockControllerProvider.notifier)
                        .setDelay(delay);
                  },
                  child: Column(
                    children: [
                      for (final delay in LockDelay.values)
                        RadioListTile<LockDelay>(
                          value: delay,
                          title: Text(delay.label),
                          enabled: lock.enabled,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
