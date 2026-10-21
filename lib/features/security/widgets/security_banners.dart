import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';
import 'package:couple_app/features/security/device_trust_controller.dart';
import 'package:couple_app/features/security/models/security_event.dart';
import 'package:couple_app/features/security/providers/security_providers.dart';
import 'package:couple_app/features/security/screens/security_screen.dart';
import 'package:couple_app/features/security/widgets/device_check_dialog.dart';

/// Both sign-in protection banners, stacked: the partner's new phone
/// waiting for this user ([DeviceCheckBanner]) and notices about this
/// user's own account ([SecurityNoticeBanner]). Takes no space when there
/// is nothing to say.
class SecurityBanners extends StatelessWidget {
  const SecurityBanners({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    mainAxisSize: MainAxisSize.min,
    children: [DeviceCheckBanner(), SecurityNoticeBanner()],
  );
}

/// "Asha signed in on a new phone. Is it really them?" with Review, while
/// the partner's check waits for an answer.
class DeviceCheckBanner extends ConsumerWidget {
  const DeviceCheckBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checks = ref.watch(partnerDeviceChecksProvider).value ?? const [];
    if (checks.isEmpty) return const SizedBox.shrink();
    final check = checks.first;
    final name = ref.watch(partnerNameProvider);
    return _BannerCard(
      key: const Key('device-check-banner'),
      preset: GradientPreset.lavender,
      icon: Icons.phone_android_rounded,
      text:
          '$name signed in on a new phone (${check.deviceName}). Is it '
          'really them?',
      actions: [
        _BannerAction(
          key: const Key('device-check-review'),
          label: 'Review',
          filled: true,
          onPressed: () => showDeviceCheckDialog(context, check),
        ),
      ],
    );
  }
}

/// The newest notice about this user's own account, from their other
/// phones' point of view: a sign-in the partner stopped, a new phone
/// waiting out its 7 days ("It wasn't me" pauses it for 30 days), or a new
/// phone that got in.
class SecurityNoticeBanner extends ConsumerStatefulWidget {
  const SecurityNoticeBanner({super.key});

  @override
  ConsumerState<SecurityNoticeBanner> createState() =>
      _SecurityNoticeBannerState();
}

class _SecurityNoticeBannerState extends ConsumerState<SecurityNoticeBanner> {
  /// Waiting notices closed for now (they stay, for "It wasn't me" later).
  final _hidden = <String>{};
  bool _busy = false;

  Future<void> _dismiss(SecurityEvent event) async {
    try {
      await ref
          .read(deviceTrustServiceProvider)
          .deleteEvent(ref.read(currentUidProvider), event.id);
    } catch (_) {
      if (mounted) context.showSnackMessage('Couldn\'t update. Try again.');
    }
  }

  Future<void> _wasntMe(SecurityEvent event) async {
    setState(() => _busy = true);
    try {
      final service = ref.read(deviceTrustServiceProvider);
      final uid = ref.read(currentUidProvider);
      final until = ref
          .read(securityClockProvider)()
          .add(DeviceTrustController.blockFor);
      await service.blockNewPhones(uid, until);
      await service.deleteEvent(uid, event.id);
      if (mounted) {
        context.showSnackMessage(
          'Thanks. New phones can\'t get in by waiting for 30 days.',
        );
      }
    } catch (_) {
      if (mounted) context.showSnackMessage('Couldn\'t update. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notices = [
      for (final e in ref.watch(securityNoticesProvider))
        if (!_hidden.contains(e.id)) e,
    ];
    if (notices.isEmpty) return const SizedBox.shrink();
    final event = notices.first;

    return switch (event.type) {
      SecurityEventType.newPhoneWaiting => _BannerCard(
        key: const Key('security-notice-waiting'),
        preset: GradientPreset.ocean,
        icon: Icons.hourglass_top_rounded,
        text:
            '${event.deviceName} signed in with your number and is waiting '
            '7 days to open your account. If that\'s you, there\'s nothing '
            'to do.',
        onClose: () => setState(() => _hidden.add(event.id)),
        actions: [
          _BannerAction(
            key: const Key('security-notice-wasnt-me'),
            label: 'It wasn\'t me',
            filled: true,
            onPressed: _busy ? null : () => _wasntMe(event),
          ),
        ],
      ),
      SecurityEventType.newPhoneRejected => _BannerCard(
        key: const Key('security-notice-rejected'),
        preset: GradientPreset.ocean,
        icon: Icons.shield_outlined,
        text:
            'A sign-in on ${event.deviceName} was stopped: '
            '${ref.watch(partnerNameProvider)} didn\'t recognise it. Your '
            'space stayed private.',
        actions: [_BannerAction(label: 'OK', onPressed: () => _dismiss(event))],
      ),
      SecurityEventType.newPhoneApproved => _BannerCard(
        key: const Key('security-notice-approved'),
        preset: GradientPreset.ocean,
        icon: Icons.phone_android_rounded,
        text: 'Your account was opened on a new phone: ${event.deviceName}.',
        actions: [
          _BannerAction(
            label: 'Not you?',
            onPressed: () => Navigator.of(context).push(SecurityScreen.route()),
          ),
          _BannerAction(
            label: 'OK',
            filled: true,
            onPressed: () => _dismiss(event),
          ),
        ],
      ),
    };
  }
}

class _BannerAction {
  const _BannerAction({
    this.key,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final Key? key;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;
}

/// A slim gradient card: icon, text, and small pill buttons.
class _BannerCard extends StatelessWidget {
  const _BannerCard({
    super.key,
    required this.preset,
    required this.icon,
    required this.text,
    required this.actions,
    this.onClose,
  });

  final GradientPreset preset;
  final IconData icon;
  final String text;
  final List<_BannerAction> actions;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: AnimatedGradientCard(
        preset: preset,
        radius: 20,
        sheen: false,
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTile(icon: icon, preset: preset, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: preset.foreground(b),
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: preset.foregroundMuted(b),
                    ),
                    onPressed: onClose,
                  )
                else
                  const SizedBox(width: 6),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final a in actions)
                  a.filled
                      ? FilledButton(
                          key: a.key,
                          onPressed: a.onPressed,
                          style: pillButtonStyle(
                            context,
                            preset: preset,
                            minimumSize: const Size(0, 38),
                          ),
                          child: Text(a.label),
                        )
                      : TextButton(
                          key: a.key,
                          onPressed: a.onPressed,
                          style: TextButton.styleFrom(
                            foregroundColor: preset.isDarkIn(b)
                                ? preset.accent(b)
                                : preset.ink,
                            minimumSize: const Size(0, 38),
                          ),
                          child: Text(a.label),
                        ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
