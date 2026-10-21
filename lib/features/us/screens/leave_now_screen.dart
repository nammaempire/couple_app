import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/data/end_pairing_gateway.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/couple/providers/separation_providers.dart';
import 'package:couple_app/features/onboarding/widgets/busy_button_label.dart';
import 'package:couple_app/features/onboarding/widgets/pairing_error_text.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';

/// "I need to leave now": ends the pairing at once, deleting everything for
/// both, after typing LEAVE and ticking that they understand.
///
/// Reached only after the phone's lock (see `EndPairingScreen`). The partner
/// only ever sees "This pairing has ended". Needs the server; when it isn't
/// there yet, explains and offers the 14-day way instead.
class LeaveNowScreen extends ConsumerStatefulWidget {
  const LeaveNowScreen({super.key});

  static const word = 'LEAVE';

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const LeaveNowScreen());

  @override
  ConsumerState<LeaveNowScreen> createState() => _LeaveNowScreenState();
}

enum _Phase { confirm, ending, needsServer }

class _LeaveNowScreenState extends ConsumerState<LeaveNowScreen> {
  late final EndPairingGateway _gateway;
  late final String _coupleId;
  late final String _uid;

  final _typed = TextEditingController();
  bool _understood = false;
  _Phase _phase = _Phase.confirm;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _gateway = ref.read(endPairingGatewayProvider);
    _coupleId = ref.read(currentCoupleIdProvider);
    _uid = ref.read(currentUidProvider);
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _typed.dispose();
    super.dispose();
  }

  Timer? _fallback;

  void _toRoot() {
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  bool get _ready =>
      _typed.text.trim().toUpperCase() == LeaveNowScreen.word && _understood;

  Future<void> _leave() async {
    if (!_ready) return;
    setState(() {
      _phase = _Phase.ending;
      _error = null;
    });
    try {
      await _gateway.leaveNow(_coupleId);
      // Ended, or the server is already ending it: the profile stream
      // takes this user on to "your pairing has ended" (see build). If it
      // is slow, go back to the app, which shows "Ending your pairing…".
      _fallback = Timer(const Duration(seconds: 15), _toRoot);
    } on EndPairingException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.failure == EndPairingFailure.unavailable) {
          _phase = _Phase.needsServer;
        } else {
          _phase = _Phase.confirm;
          _error = 'Couldn\'t end it right now. Try again in a moment.';
        }
      });
    }
  }

  /// The usual way: ask to end it in 14 days.
  Future<void> _useWaitingRoute() async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    try {
      if (ref.read(separationProvider) == null) {
        await ref
            .read(separationServiceProvider)
            .request(coupleId: _coupleId, uid: _uid, current: null);
      }
      navigator.popUntil((r) => r.isFirst);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        context.showSnackMessage('Couldn\'t do that. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Unpaired: the pairing has ended. Uncover the ended screen.
    ref.listen(currentUserProvider.select((u) => u.coupleId), (_, id) {
      if (id == null) _toRoot();
    });
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final partner = ref.watch(partnerNameProvider);
    const preset = GradientPreset.lavender;

    final Widget body = switch (_phase) {
      _Phase.ending => Column(
        key: const ValueKey('ending'),
        children: [
          const SizedBox(height: 60),
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 22),
          Text(
            'Ending your pairing…',
            style: romanceSerif(
              theme.textTheme.headlineSmall,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'This takes a moment.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      _Phase.needsServer => _NeedsServer(
        partner: partner,
        busy: _busy,
        onUseWaitingRoute: _useWaitingRoute,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      _Phase.confirm => Column(
        key: const ValueKey('confirm'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: GlowBadge(
              preset: preset,
              icon: Icons.shield_outlined,
              size: 68,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Leave now',
            textAlign: TextAlign.center,
            style: romanceSerif(theme.textTheme.headlineMedium).copyWith(
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This ends your pairing straight away. Everything you both '
            'shared, including messages, photos, memories and Private, is '
            'deleted now, for both of you. $partner will only see that the '
            'pairing has ended.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          FrostedForm(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('leave-word'),
                  controller: _typed,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Type LEAVE to confirm',
                    prefixIcon: Icon(Icons.keyboard_outlined),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                // Its own Material, so the tick's ink shows on the glass.
                Material(
                  type: MaterialType.transparency,
                  child: CheckboxListTile(
                    key: const Key('leave-understood'),
                    value: _understood,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: dark
                        ? preset.accent(theme.brightness)
                        : preset.ink,
                    title: Text(
                      'I understand everything is deleted now for both of us',
                      style: theme.textTheme.bodyMedium,
                    ),
                    onChanged: (v) => setState(() => _understood = v ?? false),
                  ),
                ),
                PairingErrorText(error: _error),
                const SizedBox(height: 14),
                FilledButton(
                  key: const Key('leave-now-confirm'),
                  onPressed: _ready ? _leave : null,
                  style: pillButtonStyle(context, preset: preset),
                  child: const Text('End it now'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GlassPanel(
            dark: dark,
            radius: 20,
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.support_agent_rounded, color: preset.ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'If you are in danger, call your local emergency number '
                    '(112 in India).',
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    };

    return PopScope(
      canPop: _phase != _Phase.ending,
      child: RomanceBackdrop(
        preset: preset,
        strength: .45,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: romanceAppBar(
            leading: _phase == _Phase.ending
                ? null
                : BackButton(onPressed: () => Navigator.of(context).maybePop()),
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: body,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NeedsServer extends StatelessWidget {
  const _NeedsServer({
    required this.partner,
    required this.busy,
    required this.onUseWaitingRoute,
    required this.onBack,
  });

  final String partner;
  final bool busy;
  final VoidCallback onUseWaitingRoute;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    const preset = GradientPreset.sunny;
    return Column(
      key: const ValueKey('needs-server'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        AnimatedGradientCard(
          preset: preset,
          radius: 26,
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconTile(
                icon: Icons.cloud_off_outlined,
                preset: preset,
                size: 44,
              ),
              const SizedBox(height: 12),
              Text(
                'This needs our server',
                style: romanceSerif(theme.textTheme.titleLarge).copyWith(
                  fontWeight: FontWeight.w700,
                  color: preset.foreground(b),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Leaving straight away deletes everything on our server, '
                'and that part isn\'t switched on yet. You can still end your '
                'pairing the usual way: it ends within 14 days, Private '
                'closes and sharing stops meanwhile, and you can mute '
                '$partner.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: preset.foregroundMuted(b),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FilledButton(
          key: const Key('leave-use-14-days'),
          onPressed: busy ? null : onUseWaitingRoute,
          style: pillButtonStyle(context, preset: GradientPreset.ocean),
          child: BusyButtonLabel(busy: busy, label: 'Use the 14-day route'),
        ),
        const SizedBox(height: 6),
        TextButton(onPressed: busy ? null : onBack, child: const Text('Back')),
      ],
    );
  }
}
