import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/app_lock/app_lock_controller.dart';
import 'package:couple_app/features/app_lock/widgets/app_lock_screen.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';

/// Whether the lock screen is up: the app is locked and someone is signed
/// in. The welcome and sign-in screens are never locked.
bool _lockShowing(WidgetRef ref) =>
    ref.read(appLockControllerProvider).locked &&
    ref.read(authStateProvider).value != null;

/// Wraps the [MaterialApp]: tells the app lock about lifecycle and sign-in
/// changes, and swallows the system back button while the lock is up.
///
/// It sits above the app, rather than in [MaterialApp.builder] with
/// [AppLockOverlay], so it sees the back button before the app's navigator
/// does; otherwise back would pop the screens hidden behind the lock.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The listener in build only hears changes; catch a sign-in state that
    // was already known before the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = ref.read(authStateProvider);
      if (!auth.hasValue) return;
      ref
          .read(appLockControllerProvider.notifier)
          .setSignedIn(auth.value != null);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(appLockControllerProvider.notifier).handleLifecycle(state);
  }

  @override
  Future<bool> didPopRoute() async => _lockShowing(ref);

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateProvider, (previous, next) {
      if (!next.hasValue) return;
      ref
          .read(appLockControllerProvider.notifier)
          .setSignedIn(next.value != null);
    });
    return widget.child;
  }
}

/// For [MaterialApp.builder]: covers every route, dialog and sheet with the
/// lock screen while the app is locked.
///
/// The app underneath stays mounted, so a call keeps going behind the lock.
/// The lock screen asks for the fingerprint, face or PIN by itself once each
/// time it appears.
class AppLockOverlay extends ConsumerStatefulWidget {
  const AppLockOverlay({super.key, required this.child});

  /// The app's navigator.
  final Widget child;

  @override
  ConsumerState<AppLockOverlay> createState() => _AppLockOverlayState();
}

class _AppLockOverlayState extends ConsumerState<AppLockOverlay> {
  /// The last [AppLockState.lockCount] the prompt was shown for.
  int _promptedFor = 0;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Locked while in the background: prompt once the app is back.
    _lifecycle = AppLifecycleListener(onResume: _autoPrompt);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _autoPrompt() {
    if (!mounted || !_lockShowing(ref)) return;
    final lock = ref.read(appLockControllerProvider);
    if (lock.authenticating || lock.lockCount == _promptedFor) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _promptedFor = lock.lockCount;
    _unlock();
  }

  Future<void> _unlock() async {
    final controller = ref.read(appLockControllerProvider.notifier);
    await controller.unlock();
    // The prompt itself can briefly background the app on some phones;
    // don't answer that with a second prompt.
    if (mounted) _promptedFor = ref.read(appLockControllerProvider).lockCount;
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockControllerProvider);
    final uid = ref.watch(authStateProvider.select((auth) => auth.value?.uid));
    final showing = lock.locked && uid != null;
    if (showing && lock.lockCount != _promptedFor) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoPrompt());
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Always the first child, so the app keeps its state when the lock
        // comes and goes.
        ExcludeFocus(
          excluding: showing,
          child: ExcludeSemantics(excluding: showing, child: widget.child),
        ),
        if (showing)
          _LockedView(
            uid: uid,
            authenticating: lock.authenticating,
            failed: lock.failed,
            onUnlock: _unlock,
          ),
      ],
    );
  }
}

/// The lock screen with the couple's pictures, once they have loaded.
class _LockedView extends ConsumerWidget {
  const _LockedView({
    required this.uid,
    required this.authenticating,
    required this.failed,
    required this.onUnlock,
  });

  final String uid;
  final bool authenticating;
  final bool failed;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider(uid)).value;
    // Errors (for example before this user's profile has loaded) just mean
    // no partner picture.
    final partner = me?.coupleId == null
        ? null
        : ref.watch(partnerProvider).value;
    return AppLockScreen(
      me: me,
      partner: partner,
      authenticating: authenticating,
      failed: failed,
      onUnlock: onUnlock,
    );
  }
}
