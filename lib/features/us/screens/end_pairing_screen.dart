import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/data/separation_service.dart';
import 'package:couple_app/features/couple/models/separation.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/couple/providers/separation_providers.dart';
import 'package:couple_app/features/couple/widgets/separation_banner.dart';
import 'package:couple_app/features/onboarding/widgets/busy_button_label.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';
import 'package:couple_app/features/us/screens/leave_now_screen.dart';
import 'package:couple_app/features/us/widgets/confirm_its_you.dart';

/// A calm explainer before asking to end the pairing: what the partner
/// sees, how long it takes, what closes meanwhile and what is deleted.
///
/// "End our pairing" asks the phone's lock (or typing END) first. A quiet
/// link at the bottom leads to "I need to leave now".
class EndPairingScreen extends ConsumerStatefulWidget {
  const EndPairingScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const EndPairingScreen());

  @override
  ConsumerState<EndPairingScreen> createState() => _EndPairingScreenState();
}

class _EndPairingScreenState extends ConsumerState<EndPairingScreen> {
  late final SeparationService _service;
  late final String _coupleId;
  late final String _uid;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service = ref.read(separationServiceProvider);
    _coupleId = ref.read(currentCoupleIdProvider);
    _uid = ref.read(currentUidProvider);
  }

  Future<void> _end() async {
    final ok = await confirmItsYou(
      context,
      ref,
      reason: 'Confirm it\'s you to end your pairing',
      fallbackWord: 'END',
      fallbackTitle: 'End your pairing?',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.request(
        coupleId: _coupleId,
        uid: _uid,
        current: ref.read(separationProvider),
      );
      if (!mounted) return;
      final when = ref
          .read(separationClockProvider)()
          .add(Separation.waitingPeriod);
      final navigator = Navigator.of(context);
      context.showSnackMessage(
        'Your pairing ends on ${separationDate(when)}. You can cancel any '
        'time before then.',
      );
      navigator.pop();
    } on SeparationException catch (e) {
      if (mounted) context.showSnackMessage(e.message);
    } catch (_) {
      if (mounted) context.showSnackMessage('Couldn\'t do that. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leaveNow() async {
    final ok = await confirmItsYou(
      context,
      ref,
      reason: 'Confirm it\'s you to leave now',
    );
    if (!ok || !mounted) return;
    await Navigator.of(context).pushReplacement(LeaveNowScreen.route());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final partner = ref.watch(partnerNameProvider);
    const preset = GradientPreset.ocean;

    return RomanceBackdrop(
      preset: preset,
      strength: .5,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: romanceAppBar(
          leading: BackButton(
            onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
          ),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: staggered([
                    const Center(
                      child: GlowBadge(
                        preset: preset,
                        icon: Icons.spa_outlined,
                        size: 72,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Ending your pairing',
                      textAlign: TextAlign.center,
                      style: romanceSerif(theme.textTheme.headlineMedium)
                          .copyWith(
                            fontWeight: FontWeight.w700,
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'It\'s okay to take this step. Here is what happens, so '
                      'nothing comes as a surprise to either of you.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 20),
                    GlassPanel(
                      dark: dark,
                      radius: 24,
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                      child: Column(
                        children: [
                          _Step(
                            icon: Icons.mark_chat_unread_outlined,
                            preset: GradientPreset.lavender,
                            title: '$partner is told, gently',
                            body:
                                'They can agree, or say they don\'t want '
                                'this. Either way, you\'ll see it here.',
                          ),
                          _Step(
                            icon: Icons.event_outlined,
                            preset: GradientPreset.ocean,
                            title: 'It ends in 14 days',
                            body:
                                'Or 7 days after $partner agrees, if that\'s '
                                'sooner. You can cancel any time before then.',
                          ),
                          const _Step(
                            icon: Icons.lock_outline_rounded,
                            preset: GradientPreset.mint,
                            title: 'Some things close while you wait',
                            body:
                                'Private closes, screenshots of the chat are '
                                'blocked, and nothing can be shared or saved '
                                'out of the app. You can still talk.',
                          ),
                          const _Step(
                            icon: Icons.delete_outline_rounded,
                            preset: GradientPreset.peach,
                            title: 'Then everything is deleted',
                            body:
                                'Messages, photos, memories and everything '
                                'else you shared, for both of you.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      key: const Key('end-pairing-confirm'),
                      onPressed: _busy ? null : _end,
                      style: pillButtonStyle(context, preset: preset),
                      child: BusyButtonLabel(
                        busy: _busy,
                        label: 'End our pairing',
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      style: TextButton.styleFrom(
                        foregroundColor: dark
                            ? preset.accent(theme.brightness)
                            : preset.ink,
                      ),
                      child: const Text('Not now'),
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: TextButton(
                        key: const Key('leave-now-link'),
                        onPressed: _busy ? null : _leaveNow,
                        style: TextButton.styleFrom(
                          foregroundColor: scheme.onSurfaceVariant,
                          textStyle: theme.textTheme.bodySmall?.copyWith(
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        child: const Text(
                          'I\'m not safe / I need to leave now',
                        ),
                      ),
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

class _Step extends StatelessWidget {
  const _Step({
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
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
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
