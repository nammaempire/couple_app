import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/onboarding/widgets/busy_button_label.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';
import 'package:couple_app/features/security/models/device_check.dart';
import 'package:couple_app/features/security/providers/security_providers.dart';

/// Asks this user whether the partner really signed in on a new phone.
/// True for yes, false for no, null when put off for later (the banner
/// keeps asking).
Future<bool?> showDeviceCheckDialog(BuildContext context, DeviceCheck check) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeviceCheckDialog(check: check),
    );

/// "Asha signed in on a new phone (Pixel 9). Is this really Asha? Ask
/// which number they see: 47", with "Yes, it's Asha" and "No, it's not".
///
/// Closes by itself if the new phone gives up (the check disappears).
class DeviceCheckDialog extends ConsumerStatefulWidget {
  const DeviceCheckDialog({super.key, required this.check});

  final DeviceCheck check;

  @override
  ConsumerState<DeviceCheckDialog> createState() => _DeviceCheckDialogState();
}

class _DeviceCheckDialogState extends ConsumerState<DeviceCheckDialog> {
  bool? _busy;
  String? _error;

  Future<void> _decide(bool approved) async {
    setState(() {
      _busy = approved;
      _error = null;
    });
    try {
      await ref
          .read(deviceTrustServiceProvider)
          .decideCheck(
            cid: ref.read(currentCoupleIdProvider),
            check: widget.check,
            decidedBy: ref.read(currentUidProvider),
            approved: approved,
          );
      if (mounted) Navigator.of(context).pop(approved);
    } catch (e) {
      debugPrint('device check decision failed: $e');
      if (mounted) {
        setState(() {
          _busy = null;
          _error = 'Couldn\'t send your answer. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // The new phone gave up or someone already answered: nothing to ask.
    ref.listen(partnerDeviceChecksProvider, (_, next) {
      final checks = next.value;
      if (checks == null || _busy != null) return;
      if (!checks.any((c) => c.id == widget.check.id)) {
        Navigator.of(context).maybePop();
      }
    });

    final theme = Theme.of(context);
    final b = theme.brightness;
    final name = ref.watch(partnerNameProvider);
    const preset = GradientPreset.lavender;
    final ink = b == Brightness.dark ? preset.accent(b) : preset.ink;
    final busy = _busy != null;

    return AlertDialog(
      icon: const GlowBadge(
        icon: Icons.phone_android_rounded,
        preset: GradientPreset.ocean,
        size: 56,
      ),
      title: Text(
        'Is this really $name?',
        textAlign: TextAlign.center,
        style: romanceSerif(
          theme.textTheme.headlineSmall,
        ).copyWith(fontWeight: FontWeight.w700, fontStyle: FontStyle.italic),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$name signed in on a new phone (${widget.check.deviceName}). '
            'Ask $name which number they see on it:',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 14),
          Center(
            child: AnimatedGradientCard(
              preset: preset,
              radius: 22,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 6),
              child: Text(
                '${widget.check.code}',
                key: const Key('device-check-code'),
                style: romanceSerif(
                  theme.textTheme.displayMedium,
                ).copyWith(fontWeight: FontWeight.w700, color: ink),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Only say yes if the numbers match and you\'re sure it\'s them. '
            'We check new phones in case a number ever changes hands.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowButtonSpacing: 8,
      actions: [
        // Stacked, so "Yes, it's <name>" never wraps on a narrow phone.
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              key: const Key('device-check-yes'),
              onPressed: busy ? null : () => _decide(true),
              style: pillButtonStyle(
                context,
                preset: GradientPreset.ocean,
                minimumSize: const Size(0, 48),
              ),
              child: BusyButtonLabel(
                busy: _busy == true,
                label: 'Yes, it\'s $name',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('device-check-no'),
              onPressed: busy ? null : () => _decide(false),
              style: pillOutlineStyle(
                context,
                preset: GradientPreset.ocean,
                minimumSize: const Size(0, 48),
              ),
              child: _busy == false
                  ? const BusyButtonLabel(busy: true, label: '')
                  : const Text('No, it\'s not'),
            ),
          ],
        ),
        Center(
          child: TextButton(
            onPressed: busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Decide later'),
          ),
        ),
      ],
    );
  }
}
