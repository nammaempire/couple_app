import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:flutter/services.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/home/models/love_tap.dart';

/// One-tap love messages: each chip buzzes the partner's phone.
class LoveTapsCard extends StatefulWidget {
  const LoveTapsCard({
    super.key,
    required this.partnerName,
    required this.enabled,
    required this.onSend,
  });

  final String partnerName;
  final bool enabled;
  final Future<void> Function(LoveTap tap) onSend;

  @override
  State<LoveTapsCard> createState() => _LoveTapsCardState();
}

class _LoveTapsCardState extends State<LoveTapsCard> {
  /// The tap just sent, briefly highlighted as confirmation.
  LoveTap? _justSent;

  Future<void> _send(LoveTap tap) async {
    await HapticFeedback.mediumImpact();
    setState(() => _justSent = tap);
    try {
      await widget.onSend(tap);
    } catch (_) {
      if (mounted) {
        context.showSnackMessage('Could not send. Check your connection.');
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted && _justSent == tap) setState(() => _justSent = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sent = _justSent;

    return AnimatedGradientCard(
      preset: GradientPreset.sunset,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Send love',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              key: ValueKey(sent),
              !widget.enabled
                  ? 'Available once you\'re paired.'
                  : sent == null
                  ? 'One tap and ${widget.partnerName}\'s phone buzzes.'
                  : 'Sent ${sent.label.toLowerCase()} ${sent.emoji}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: sent == null
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.primary,
                fontWeight: sent == null ? null : FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final tap in LoveTap.values)
                Expanded(
                  child: _TapButton(
                    tap: tap,
                    highlighted: sent == tap,
                    onPressed: widget.enabled ? () => _send(tap) : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TapButton extends StatelessWidget {
  const _TapButton({
    required this.tap,
    required this.highlighted,
    required this.onPressed,
  });

  final LoveTap tap;
  final bool highlighted;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: 'Send ${tap.label}',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Column(
            children: [
              AnimatedScale(
                scale: highlighted ? 1.18 : 1,
                duration: const Duration(milliseconds: 180),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: highlighted
                        ? theme.colorScheme.primary.withValues(alpha: .22)
                        : Colors.white.withValues(
                            alpha: theme.brightness == Brightness.dark
                                ? .12
                                : .62,
                          ),
                  ),
                  child: Text(tap.emoji, style: const TextStyle(fontSize: 24)),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tap.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
