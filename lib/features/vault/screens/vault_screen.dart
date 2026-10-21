import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/providers/core_providers.dart';
import 'package:couple_app/core/services/screen_privacy.dart';
import 'package:couple_app/features/app_lock/providers/app_lock_providers.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/couple/providers/separation_providers.dart';
import 'package:couple_app/features/vault/data/vault_service.dart';
import 'package:couple_app/features/vault/models/vault_age.dart';
import 'package:couple_app/features/vault/providers/vault_providers.dart';
import 'package:couple_app/features/vault/screens/vault_home_screen.dart';
import 'package:couple_app/features/vault/screens/vault_lock_screen.dart';
import 'package:couple_app/features/vault/screens/vault_notice_screen.dart';
import 'package:couple_app/features/vault/screens/vault_setup_screen.dart';
import 'package:couple_app/features/vault/vault_session.dart';
import 'package:couple_app/features/vault/widgets/vault_look.dart';

/// Opens the vault: `Navigator.push(VaultScreen.route())`.
///
/// It decides what to show (the age check, setup, waiting for approval, the
/// lock, or the open vault), keeps screenshots and the recent-apps preview
/// blocked while it is open, and locks when the app goes to the background,
/// after two idle minutes, or when it closes.
class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const VaultScreen());

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen>
    with WidgetsBindingObserver {
  late final VaultSession _session;
  late final ScreenPrivacyGuard _guard;
  bool _inSetup = false;
  bool _registering = false;
  String? _registerProblem;
  bool _confirmingAge = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = ref.read(vaultSessionProvider.notifier);
    _guard = ref.read(screenPrivacyGuardProvider);
    // FLAG_SECURE for as long as any vault screen is up: no screenshots,
    // no recordings, no recent-apps preview.
    _guard.claim(this, secure: true, onScreenshot: () {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _guard.release(this);
    // Leaving the vault locks it (after this frame; providers can't change
    // while the tree is being torn down).
    final session = _session;
    Future.microtask(session.lock);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _session.handleLifecycle(state);

  /// Closes anything open over the vault (a photo, a dialog) when it locks.
  void _closeOverlays() {
    final route = ModalRoute.of(context);
    if (route == null || route.isCurrent) return;
    Navigator.of(context).popUntil((r) => r == route);
  }

  Future<void> _offerBiometric() async {
    final state = ref.read(vaultSessionProvider);
    if (state.biometricAsked || state.biometric) return;
    final auth = ref.read(biometricAuthProvider);
    if (!await auth.canAuthenticate() || !mounted) return;
    final yes = await showVaultDialog<bool>(
      context,
      (context) => AlertDialog(
        icon: const Icon(Icons.fingerprint, color: vaultGold, size: 36),
        title: const Text('Open with fingerprint or face?'),
        content: const Text(
          'On this phone only. You can change this in ⋮ › Devices.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            style: vaultButtonStyle(context, minimumSize: const Size(88, 40)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Use it'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    await _session.setBiometric(yes == true);
  }

  Future<void> _register() async {
    if (_registering) return;
    _registering = true;
    try {
      await _session.register();
    } on VaultDeviceLimitException catch (e) {
      if (mounted) setState(() => _registerProblem = e.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => _registerProblem =
              'Couldn\'t add this phone. Check your connection and try again.',
        );
      }
    } finally {
      _registering = false;
    }
  }

  Future<void> _confirmAge() async {
    setState(() => _confirmingAge = true);
    try {
      await ref.read(authServiceProvider).confirmAdult();
    } finally {
      if (mounted) setState(() => _confirmingAge = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // While the pairing ends the vault is closed for both; the rules
    // refuse every read and write, so nothing below is even subscribed.
    if (ref.watch(separationActiveProvider)) {
      if (_session.isUnlocked) Future.microtask(_session.lock);
      return VaultNoticeScreen(
        icon: Icons.lock_outline_rounded,
        title: 'Private is closed',
        text:
            'Private is closed while your pairing ends. Nothing in it can '
            'be opened or added.',
        primaryLabel: 'Back',
        onPrimary: () => Navigator.of(context).maybePop(),
      );
    }

    ref.listen(vaultSessionProvider.select((s) => s.lockCount), (_, _) {
      _closeOverlays();
    });
    ref.listen(vaultSessionProvider.select((s) => s.unlocked), (was, now) {
      if (now && was == false && !_inSetup) _offerBiometric();
    });
    ref.listen(vaultMetaProvider, (_, next) {
      // Deleted by the partner while open.
      if (next.hasValue && next.value == null && _session.isUnlocked) {
        _session.lock();
      }
    });

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _session.touch(),
      child: _page(context),
    );
  }

  Widget _page(BuildContext context) {
    final partner = ref.watch(partnerNameProvider);
    switch (ref.watch(vaultAgeStatusProvider)) {
      case VaultAgeStatus.underage:
        return VaultNoticeScreen(
          icon: Icons.favorite_border_rounded,
          title: 'Private isn\'t available',
          text:
              'Private is only for couples where both of you are 18 or '
              'older. Everything else in the app is still all yours.',
          primaryLabel: 'Back',
          onPrimary: () => Navigator.of(context).maybePop(),
        );
      case VaultAgeStatus.confirmMine:
        return VaultNoticeScreen(
          icon: Icons.verified_user_outlined,
          title: 'Just for grown-ups',
          text:
              'Private is for adults. Please confirm you\'re 18 or older '
              'to continue.',
          primaryLabel: 'I\'m 18 or older',
          onPrimary: _confirmAge,
          busy: _confirmingAge,
          secondaryLabel: 'Not now',
          onSecondary: () => Navigator.of(context).maybePop(),
        );
      case VaultAgeStatus.waitingForPartner:
        return VaultNoticeScreen(
          icon: Icons.hourglass_top_rounded,
          title: 'Waiting for $partner',
          text:
              'Private is for adults, so $partner needs to confirm they\'re '
              '18 or older too. Ask them to open Private on their phone.',
          primaryLabel: 'OK',
          onPrimary: () => Navigator.of(context).maybePop(),
        );
      case VaultAgeStatus.ok:
        break;
    }

    final access = ref.watch(vaultAccessProvider);
    if (access == VaultAccess.notSetUp) _inSetup = true;
    if (_inSetup) {
      return VaultSetupScreen(
        onFinished: () => setState(() => _inSetup = false),
      );
    }

    switch (access) {
      case VaultAccess.loading:
        return const VaultBackdrop(
          child: Center(child: CircularProgressIndicator(color: vaultGold)),
        );
      case VaultAccess.notSetUp:
        // Handled above.
        return const SizedBox.shrink();
      case VaultAccess.unregistered:
        if (_registerProblem == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_register());
          });
        }
        return _waiting(partner, problem: _registerProblem);
      case VaultAccess.pending:
        return _waiting(partner);
      case VaultAccess.locked:
        return const VaultLockScreen();
      case VaultAccess.unlocked:
        return const VaultHomeScreen();
    }
  }

  Widget _waiting(String partner, {String? problem}) {
    final meta = ref.watch(vaultMetaProvider).value;
    final myUid = ref.watch(currentUidProvider);
    final identity = ref.watch(vaultSessionProvider).identity;
    final partnerCanApprove =
        meta?.devices.values.any((d) => d.approved && d.uid != myUid) ?? true;
    final approver = partnerCanApprove ? partner : 'your other phone';
    final fingerprint = meta?.devices[identity?.deviceId]?.fingerprint;

    return VaultNoticeScreen(
      icon: Icons.phonelink_lock_outlined,
      title: partnerCanApprove
          ? 'Waiting for $partner to approve this phone'
          : 'Waiting for approval',
      text:
          problem ??
          (partnerCanApprove
              ? 'Ask $partner to open the Vault on their phone. They\'ll '
                    'see a request to approve this one.'
              : 'Open the Vault on $approver to approve this one.'),
      extra: fingerprint == null
          ? null
          : VaultSafetyCode(
              code: fingerprint,
              caption: 'Check that $approver shows the same code.',
            ),
      busy: problem == null && fingerprint == null,
      primaryLabel: problem == null ? null : 'Try again',
      onPrimary: problem == null
          ? null
          : () {
              setState(() => _registerProblem = null);
            },
    );
  }
}
