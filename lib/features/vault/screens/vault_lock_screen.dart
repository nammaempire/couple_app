import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/vault/providers/vault_providers.dart';
import 'package:couple_app/features/vault/vault_session.dart';
import 'package:couple_app/features/vault/widgets/vault_code_pad.dart';
import 'package:couple_app/features/vault/widgets/vault_look.dart';

/// The vault's lock: six dots, a number pad, the fingerprint key once it's
/// on for this phone, the cooldown after too many wrong codes, and help for
/// a forgotten code.
///
/// The real and decoy codes are handled the same way here; nothing on this
/// screen says which vault opened.
class VaultLockScreen extends ConsumerStatefulWidget {
  const VaultLockScreen({super.key, this.offerBiometric = true});

  /// Show the fingerprint prompt by itself once, when first shown.
  final bool offerBiometric;

  @override
  ConsumerState<VaultLockScreen> createState() => _VaultLockScreenState();
}

class _VaultLockScreenState extends ConsumerState<VaultLockScreen> {
  Timer? _tick;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _syncTicker();
    if (widget.offerBiometric) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ref.read(vaultSessionProvider).biometric) _biometric();
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Ticks once a second while a cooldown runs, for the countdown.
  void _syncTicker() {
    final until = ref.read(vaultSessionProvider).cooldownUntil;
    final now = ref.read(vaultClockProvider)();
    final cooling = until != null && now.isBefore(until);
    if (cooling && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        _syncTicker();
      });
    } else if (!cooling && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  Future<bool> _submit(String code) async {
    final session = ref.read(vaultSessionProvider.notifier);
    final result = await session.enterCode(code);
    if (!mounted) return false;
    setState(() {
      _problem = switch (result) {
        VaultUnlockResult.failed =>
          'Couldn\'t open the vault. Check your connection and try again.',
        VaultUnlockResult.notApproved =>
          'This phone isn\'t approved for the vault yet.',
        _ => null,
      };
    });
    _syncTicker();
    return result == VaultUnlockResult.unlocked;
  }

  Future<void> _biometric() async {
    final result = await ref
        .read(vaultSessionProvider.notifier)
        .unlockWithBiometrics();
    if (!mounted) return;
    if (result == VaultUnlockResult.failed) {
      setState(() => _problem = 'Couldn\'t open the vault. Try your code.');
    }
  }

  void _forgot() {
    final partner = ref.read(partnerNameProvider);
    showVaultSheet<void>(
      context,
      scrollable: true,
      (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const VaultBadge(icon: Icons.key_rounded, size: 56),
              const SizedBox(height: 14),
              const VaultTitle('Forgot the code?', size: 26),
              const SizedBox(height: 10),
              VaultText(
                'No one can recover it, not even us. That\'s what keeps '
                'it private.\n\nAsk $partner to open Private on their phone, '
                'tap ⋮ › Change code and choose a new one. Then they can '
                'tell you in person.',
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: vaultButtonStyle(context),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vaultSessionProvider);
    ref.listen(vaultSessionProvider.select((s) => s.cooldownUntil), (_, _) {
      _syncTicker();
    });
    final now = ref.watch(vaultClockProvider)();
    final until = state.cooldownUntil;
    final remaining = until?.difference(now);
    final cooling = remaining != null && remaining > Duration.zero;

    final String subtitle;
    if (cooling) {
      subtitle = 'Too many tries. Try again in ${_format(remaining)}';
    } else if (_problem != null) {
      subtitle = _problem!;
    } else {
      subtitle = 'Enter your code';
    }

    return VaultBackdrop(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const VaultBadge(size: 64),
                    const SizedBox(height: 16),
                    const VaultTitle('Private'),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        subtitle,
                        key: const Key('vault-lock-subtitle'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cooling ? vaultBlush : vaultMuted,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    VaultCodeEntry(
                      enabled: !cooling && !state.busy,
                      onSubmit: _submit,
                      leadingKey: state.biometric
                          ? VaultPadIconKey(
                              icon: Icons.fingerprint,
                              label: 'Use fingerprint or face',
                              onTap: state.busy ? null : _biometric,
                            )
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: _forgot,
                      style: TextButton.styleFrom(foregroundColor: vaultMuted),
                      child: const Text('Forgot code?'),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _format(Duration d) {
    final total = d.inSeconds + (d.inMilliseconds % 1000 > 0 ? 1 : 0);
    final m = total ~/ 60;
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
