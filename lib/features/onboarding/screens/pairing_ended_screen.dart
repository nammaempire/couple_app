import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/couple/data/separation_service.dart';
import 'package:couple_app/features/couple/providers/separation_providers.dart';
import 'package:couple_app/features/onboarding/widgets/busy_button_label.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';

/// Shown once after the server ends a pairing (`users/{me}.pairingEndedAt`),
/// then cleared, after which the auth gate shows pairing again.
///
/// The wording follows [how]: `agreed`, `oneSided`, or `leftNow`. For
/// `leftNow` it says only that the pairing has ended, never how or why, so
/// the partner learns nothing about a safety exit.
class PairingEndedScreen extends ConsumerStatefulWidget {
  const PairingEndedScreen({super.key, required this.uid, this.how});

  final String uid;
  final String? how;

  @override
  ConsumerState<PairingEndedScreen> createState() => _PairingEndedScreenState();
}

class _PairingEndedScreenState extends ConsumerState<PairingEndedScreen> {
  late final SeparationService _service;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service = ref.read(separationServiceProvider);
  }

  Future<void> _continue() async {
    setState(() => _busy = true);
    try {
      // The auth gate moves on once the marker is gone.
      await _service.clearPairingEnded(widget.uid);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      context.showSnackMessage('Couldn\'t continue. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    const preset = GradientPreset.lavender;

    final (title, body) = switch (widget.how) {
      'leftNow' => (
        'This pairing has ended',
        'Everything that was shared has been deleted.',
      ),
      'agreed' => (
        'Your pairing has ended',
        'Everything you shared has been deleted. You decided this together, '
            'and that took care.',
      ),
      _ => (
        'Your pairing has ended',
        'Everything you shared has been deleted. Be gentle with yourself '
            'today.',
      ),
    };

    return RomanceBackdrop(
      preset: preset,
      strength: .5,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: staggered([
                    const Center(
                      child: GlowBadge(
                        preset: preset,
                        icon: Icons.local_florist_outlined,
                        size: 88,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: romanceSerif(theme.textTheme.headlineMedium)
                          .copyWith(
                            fontWeight: FontWeight.w700,
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 24),
                    GlassPanel(
                      dark: dark,
                      radius: 22,
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Your account is still yours. Whenever you\'re ready, '
                        'you can start a new space.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      key: const Key('pairing-ended-continue'),
                      onPressed: _busy ? null : _continue,
                      style: pillButtonStyle(context, preset: preset),
                      child: BusyButtonLabel(busy: _busy, label: 'Continue'),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
