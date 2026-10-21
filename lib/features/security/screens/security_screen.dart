import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';
import 'package:couple_app/features/security/models/known_device.dart';
import 'package:couple_app/features/security/models/security_event.dart';
import 'package:couple_app/features/security/providers/security_providers.dart';
import 'package:couple_app/features/security/screens/confirm_new_phone_screen.dart';
import 'package:couple_app/features/security/widgets/add_recovery_email_sheet.dart';
import 'package:couple_app/features/us/widgets/settings_section_header.dart';

/// "Today", "Yesterday", "3 days ago", "12 Mar", "12 Mar 2025".
String lastSeenLabel(DateTime? at, DateTime now) {
  if (at == null) return 'Just now';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  return at.year == now.year
      ? DateFormat('d MMM').format(at)
      : DateFormat('d MMM y').format(at);
}

/// Sign-in protection, from Us → Account: the phones that can open this
/// account (remove any but this one), the recovery email, and recent
/// notices.
class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const SecurityScreen());

  static const _preset = GradientPreset.ocean;

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    KnownDevice device,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${device.name}?'),
        content: const Text(
          'If it opens your account again, it will need to confirm it\'s '
          'you first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            key: const Key('security-remove-confirm'),
            onPressed: () => Navigator.pop(context, true),
            style: pillButtonStyle(
              context,
              preset: _preset,
              minimumSize: const Size(0, 44),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(deviceTrustServiceProvider)
          .removeDevice(uid: ref.read(currentUidProvider), deviceId: device.id);
    } catch (_) {
      if (context.mounted) {
        context.showSnackMessage('Couldn\'t remove it. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final devices = ref.watch(knownDevicesProvider);
    final thisPhone = ref.watch(currentDeviceIdProvider).value;
    final reauth = ref.watch(reauthOptionsProvider);
    final events = ref.watch(securityEventsProvider).value ?? const [];
    final now = ref.watch(securityClockProvider)();

    return RomanceBackdrop(
      preset: _preset,
      strength: .45,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: romanceAppBar(
          automaticallyImplyLeading: true,
          title: const Text('Sign-in protection'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            GlassPanel(
              dark: theme.brightness == Brightness.dark,
              radius: 22,
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const GlowBadge(
                    icon: Icons.verified_user_outlined,
                    preset: _preset,
                    size: 46,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      '$newPhoneWhy When a new phone signs in, '
                      'your partner, your recovery email or a 7-day wait '
                      'confirms it\'s you.',
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),

            const SettingsSectionHeader(label: 'Your phones'),
            GradientGroup(
              preset: _preset,
              children: [
                if (devices.isLoading && !devices.hasValue)
                  const ListTile(title: Text('Loading…')),
                if (devices.hasError && !devices.hasValue)
                  const ListTile(title: Text('Couldn\'t load your phones.')),
                for (final d in devices.value ?? const <KnownDevice>[])
                  ListTile(
                    key: Key('security-device-${d.id}'),
                    leading: const IconTile(
                      icon: Icons.phone_android_rounded,
                      preset: _preset,
                      size: 40,
                    ),
                    title: Text(
                      d.id == thisPhone ? '${d.name} · this phone' : d.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Last seen ${_lower(lastSeenLabel(d.seenAt, now))}'
                      ' · ${d.via.label}',
                    ),
                    trailing: d.id == thisPhone || thisPhone == null
                        ? null
                        : TextButton(
                            key: Key('security-remove-${d.id}'),
                            style: TextButton.styleFrom(
                              foregroundColor:
                                  theme.brightness == Brightness.dark
                                  ? _preset.accent(theme.brightness)
                                  : _preset.ink,
                            ),
                            onPressed: () => _remove(context, ref, d),
                            child: const Text('Remove'),
                          ),
                  ),
              ],
            ),

            const SettingsSectionHeader(label: 'Recovery email'),
            GradientGroup(
              preset: _preset,
              children: [
                if (reauth.password)
                  ListTile(
                    leading: const Icon(Icons.mark_email_read_outlined),
                    title: Text(reauth.passwordEmail!),
                    subtitle: const Text(
                      'With your password, confirms it\'s you on a new phone',
                    ),
                  )
                else if (reauth.google)
                  ListTile(
                    leading: const Icon(Icons.account_circle_outlined),
                    title: Text(reauth.googleEmail!),
                    subtitle: const Text(
                      'Your Google account confirms it\'s you on a new phone',
                    ),
                  )
                else
                  ListTile(
                    key: const Key('security-add-email'),
                    leading: const Icon(Icons.alternate_email_rounded),
                    title: const Text('Add recovery email'),
                    subtitle: const Text(
                      'So a new phone can be confirmed in a minute',
                    ),
                    trailing: const Icon(Icons.add),
                    onTap: () => showAddRecoveryEmailSheet(context),
                  ),
              ],
            ),

            const SettingsSectionHeader(label: 'Recent activity'),
            GradientGroup(
              preset: _preset,
              children: [
                if (events.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.check_circle_outline),
                    title: Text('Nothing new'),
                    subtitle: Text(
                      'We\'ll let you know if a new phone signs in',
                    ),
                  ),
                for (final e in events.take(10))
                  ListTile(
                    key: Key('security-event-${e.id}'),
                    leading: Icon(_eventIcon(e.type)),
                    title: Text(_eventTitle(e)),
                    subtitle: Text(lastSeenLabel(e.at, now)),
                    trailing: e.type == SecurityEventType.newPhoneWaiting
                        ? null
                        : IconButton(
                            tooltip: 'Dismiss',
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => ref
                                .read(deviceTrustServiceProvider)
                                .deleteEvent(
                                  ref.read(currentUidProvider),
                                  e.id,
                                ),
                          ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              newPhoneReinstallNote,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "today", "3 days ago", but "11 Sep" keeps its capital.
  static String _lower(String label) => label.startsWith(RegExp('[A-Z][a-z]'))
      ? label[0].toLowerCase() + label.substring(1)
      : label;

  static IconData _eventIcon(SecurityEventType type) => switch (type) {
    SecurityEventType.newPhoneRejected => Icons.shield_outlined,
    SecurityEventType.newPhoneWaiting => Icons.hourglass_top_rounded,
    SecurityEventType.newPhoneApproved => Icons.phone_android_rounded,
  };

  static String _eventTitle(SecurityEvent e) => switch (e.type) {
    SecurityEventType.newPhoneRejected =>
      'Sign-in on ${e.deviceName} stopped by your partner',
    SecurityEventType.newPhoneWaiting =>
      '${e.deviceName} is waiting to open your account',
    SecurityEventType.newPhoneApproved => '${e.deviceName} was added',
  };
}
