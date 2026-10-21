import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/app_lock/app_lock_controller.dart';
import 'package:couple_app/features/app_lock/providers/app_lock_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/vault/data/vault_service.dart';
import 'package:couple_app/features/vault/vault_session.dart';
import 'package:couple_app/features/vault/widgets/vault_code_pad.dart';
import 'package:couple_app/features/vault/widgets/vault_look.dart';

enum _Step {
  intro,
  code,
  confirm,
  decoy,
  confirmDecoy,
  biometric,
  creating,
  done,
}

/// Setting the vault up, on the first partner's phone: what end-to-end
/// means, the shared code (twice), the decoy code (twice), fingerprint /
/// face, and a reminder to share the code in person.
///
/// The age check comes before this (see `VaultScreen`).
class VaultSetupScreen extends ConsumerStatefulWidget {
  const VaultSetupScreen({super.key, required this.onFinished});

  /// The vault is created and open; show it.
  final VoidCallback onFinished;

  @override
  ConsumerState<VaultSetupScreen> createState() => _VaultSetupScreenState();
}

class _VaultSetupScreenState extends ConsumerState<VaultSetupScreen> {
  _Step _step = _Step.intro;
  String _code = '';
  String _decoy = '';
  String? _hint;
  bool _canUseBiometrics = false;

  @override
  void initState() {
    super.initState();
    ref.read(biometricAuthProvider).canAuthenticate().then((ok) {
      if (mounted) _canUseBiometrics = ok;
    });
  }

  void _go(_Step step, {String? hint}) => setState(() {
    _step = step;
    _hint = hint;
  });

  void _back() {
    switch (_step) {
      case _Step.intro:
      case _Step.creating:
      case _Step.done:
        Navigator.of(context).maybePop();
      case _Step.code:
        _go(_Step.intro);
      case _Step.confirm:
        _go(_Step.code);
      case _Step.decoy:
        _go(_Step.code);
      case _Step.confirmDecoy:
        _go(_Step.decoy);
      case _Step.biometric:
        _go(_Step.decoy);
    }
  }

  Future<bool> _onCode(String code) async {
    switch (_step) {
      case _Step.code:
        _code = code;
        _go(_Step.confirm);
        return true;
      case _Step.confirm:
        if (code != _code) {
          _go(_Step.code, hint: 'Those didn\'t match. Choose your code again.');
          return false;
        }
        _go(_Step.decoy);
        return true;
      case _Step.decoy:
        if (code == _code) {
          setState(
            () => _hint = 'The decoy code must be different from your code.',
          );
          return false;
        }
        _decoy = code;
        _go(_Step.confirmDecoy);
        return true;
      case _Step.confirmDecoy:
        if (code != _decoy) {
          _go(_Step.decoy, hint: 'Those didn\'t match. Choose it again.');
          return false;
        }
        if (_canUseBiometrics) {
          _go(_Step.biometric);
        } else {
          await _create(biometric: false);
        }
        return true;
      default:
        return false;
    }
  }

  Future<void> _create({required bool biometric}) async {
    var useBiometric = false;
    if (biometric) {
      final auth = ref.read(biometricAuthProvider);
      final session = ref.read(vaultSessionProvider.notifier);
      final appLock = ref.read(appLockControllerProvider.notifier);
      useBiometric = await session.suspendWhile(
        appLock.suspendWhile(
          auth.authenticate('Use your fingerprint or face for Private'),
        ),
      );
      if (!mounted) return;
    }
    _go(_Step.creating);
    try {
      await ref
          .read(vaultSessionProvider.notifier)
          .setUp(realCode: _code, decoyCode: _decoy, biometric: useBiometric);
      if (!mounted) return;
      _go(_Step.done);
    } on VaultExistsException {
      // The partner set it up a moment earlier: this phone joins theirs.
      if (mounted) widget.onFinished();
    } catch (_) {
      if (!mounted) return;
      _go(
        _Step.biometric,
        hint: 'Couldn\'t set up the vault. Check your connection.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final partner = ref.watch(partnerNameProvider);
    return VaultBackdrop(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          leading: _step == _Step.creating
              ? const SizedBox.shrink()
              : IconButton(
                  icon: Icon(
                    _step == _Step.intro || _step == _Step.done
                        ? Icons.close
                        : Icons.arrow_back,
                  ),
                  tooltip: 'Back',
                  onPressed: _back,
                ),
          title: _progress(),
          centerTitle: true,
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: _body(context, partner),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _progress() {
    const steps = [
      _Step.intro,
      _Step.code,
      _Step.decoy,
      _Step.biometric,
      _Step.done,
    ];
    final index = switch (_step) {
      _Step.intro => 0,
      _Step.code || _Step.confirm => 1,
      _Step.decoy || _Step.confirmDecoy => 2,
      _Step.biometric || _Step.creating => 3,
      _Step.done => 4,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < steps.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i <= index ? vaultGold : Colors.white24,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }

  Widget _codePage({
    required String title,
    required String text,
    IconData icon = Icons.lock_rounded,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        VaultBadge(icon: icon, size: 56),
        const SizedBox(height: 14),
        VaultTitle(title, size: 27),
        const SizedBox(height: 8),
        VaultText(text),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: _hint == null
              ? null
              : Text(
                  _hint!,
                  key: const Key('vault-setup-hint'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: vaultBlush, fontSize: 14),
                ),
        ),
        VaultCodeEntry(onSubmit: _onCode),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _body(BuildContext context, String partner) {
    switch (_step) {
      case _Step.intro:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const VaultBadge(),
            const SizedBox(height: 18),
            const VaultTitle('A private space,\njust for you two'),
            const SizedBox(height: 22),
            const _Promise(
              emoji: '🔐',
              title: 'Not even we can see it',
              text:
                  'Photos and messages are locked on your phones before they '
                  'leave. Only your two phones hold the key.',
            ),
            const _Promise(
              emoji: '🕊️',
              title: 'If both phones are lost, it\'s gone for good',
              text:
                  'There\'s no backup key and no recovery, by design. Not '
                  'even for us.',
            ),
            const _Promise(
              emoji: '🙈',
              title: 'Never on your camera roll',
              text:
                  'Screenshots are blocked, and nothing is saved to the '
                  'gallery or left on the phone.',
            ),
            if (_hint != null) ...[
              const SizedBox(height: 8),
              Text(
                _hint!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: vaultBlush),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              style: vaultButtonStyle(context),
              onPressed: () => _go(_Step.code),
              child: const Text('Choose a code'),
            ),
            const SizedBox(height: 24),
          ],
        );
      case _Step.code:
        return _codePage(
          title: 'Choose your code',
          text: 'Six digits you\'ll both use to open Private.',
        );
      case _Step.confirm:
        return _codePage(
          title: 'Once more',
          text: 'Enter the same code again.',
        );
      case _Step.decoy:
        return _codePage(
          icon: Icons.theater_comedy_outlined,
          title: 'Now a decoy code',
          text:
              'If anyone ever makes you open Private, this code opens a '
              'second, harmless vault that looks exactly the same. Fill it '
              'with safe photos and chat.',
        );
      case _Step.confirmDecoy:
        return _codePage(
          icon: Icons.theater_comedy_outlined,
          title: 'Once more',
          text: 'Enter the decoy code again.',
        );
      case _Step.biometric:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const VaultBadge(icon: Icons.fingerprint),
            const SizedBox(height: 18),
            const VaultTitle('Open with your\nfingerprint or face?'),
            const SizedBox(height: 12),
            const VaultText(
              'On this phone only. The fingerprint opens your real vault; '
              'the code still works too.',
            ),
            if (_hint != null) ...[
              const SizedBox(height: 12),
              Text(_hint!, style: const TextStyle(color: vaultBlush)),
            ],
            const SizedBox(height: 28),
            FilledButton(
              style: vaultButtonStyle(context),
              onPressed: () => _create(biometric: true),
              child: const Text('Use fingerprint or face'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: vaultOutlineStyle(context),
              onPressed: () => _create(biometric: false),
              child: const Text('Not now'),
            ),
          ],
        );
      case _Step.creating:
        return const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: vaultGold),
            SizedBox(height: 20),
            VaultText('Making your keys…'),
          ],
        );
      case _Step.done:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const VaultBadge(icon: Icons.favorite_rounded),
            const SizedBox(height: 18),
            const VaultTitle('Your vault is ready'),
            const SizedBox(height: 14),
            VaultCard(
              child: Column(
                children: [
                  Text(
                    'Tell $partner the code in person',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: vaultGold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const VaultText(
                    'Not by text, not in chat. Keep the decoy code between '
                    'you two as well.',
                    size: 14,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            VaultText(
              'When $partner opens Private on their phone, you\'ll be asked '
              'to approve it here.',
              size: 14,
            ),
            const SizedBox(height: 28),
            FilledButton(
              style: vaultButtonStyle(context),
              onPressed: widget.onFinished,
              child: const Text('Open the vault'),
            ),
          ],
        );
    }
  }
}

class _Promise extends StatelessWidget {
  const _Promise({
    required this.emoji,
    required this.title,
    required this.text,
  });

  final String emoji;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: VaultCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    text,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: vaultMuted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
