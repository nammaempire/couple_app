import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/app_lock/data/app_lock_settings.dart';
import 'package:couple_app/features/app_lock/providers/app_lock_providers.dart';

/// The app lock: whether it is on, how soon it locks, and whether the app is
/// locked right now.
@immutable
class AppLockState {
  const AppLockState({
    required this.enabled,
    required this.delay,
    required this.locked,
    this.lockCount = 0,
    this.authenticating = false,
    this.failed = false,
  });

  final bool enabled;
  final LockDelay delay;
  final bool locked;

  /// Goes up each time the app locks, or comes back to the foreground while
  /// locked. The lock screen shows the system prompt by itself once per
  /// value.
  final int lockCount;

  /// The system prompt is up.
  final bool authenticating;

  /// The last unlock attempt failed or was cancelled.
  final bool failed;

  AppLockState copyWith({
    bool? enabled,
    LockDelay? delay,
    bool? locked,
    int? lockCount,
    bool? authenticating,
    bool? failed,
  }) {
    return AppLockState(
      enabled: enabled ?? this.enabled,
      delay: delay ?? this.delay,
      locked: locked ?? this.locked,
      lockCount: lockCount ?? this.lockCount,
      authenticating: authenticating ?? this.authenticating,
      failed: failed ?? this.failed,
    );
  }
}

/// Locks the app on a cold start and after it has been in the background for
/// the chosen delay, and unlocks it with the phone's biometrics or PIN.
///
/// [AppLockGate] feeds it lifecycle and sign-in changes. Whatever the app
/// opens itself (photo picker, camera, share sheet, Spotify, the unlock
/// prompt) goes through [suspendWhile] or [pauseLocking], so coming back
/// from it never locks.
class AppLockController extends Notifier<AppLockState> {
  /// After a suspension ends, or [pauseLocking] is called, a background that
  /// starts within this window is still ours. External apps opened through
  /// url_launcher report success before this app is actually backgrounded.
  static const grace = Duration(seconds: 3);

  late AppLockSettings _settings;
  late DateTime Function() _now;

  int _suspensions = 0;
  DateTime? _graceUntil;
  bool _signedOut = false;

  /// When the current trip to the background started; null in the
  /// foreground.
  DateTime? _backgroundSince;

  /// Whether the current trip to the background was caused by the app
  /// itself.
  bool _excused = false;

  @override
  AppLockState build() {
    _settings = ref.watch(appLockSettingsProvider);
    _now = ref.watch(appLockClockProvider);
    final enabled = _settings.enabled;
    // A cold start locks straight away. The gate only shows the lock while
    // someone is signed in, and unlocks once it learns nobody is.
    return AppLockState(
      enabled: enabled,
      delay: _settings.delay,
      locked: enabled,
      lockCount: enabled ? 1 : 0,
    );
  }

  bool get _guarding => state.enabled && !_signedOut;

  bool get _suspended {
    if (_suspensions > 0) return true;
    final until = _graceUntil;
    return until != null && !_now().isAfter(until);
  }

  /// Runs [future] (a picker, share sheet, external link, the unlock prompt)
  /// without the trip to the background it causes locking the app.
  Future<T> suspendWhile<T>(Future<T> future) async {
    _suspensions++;
    try {
      return await future;
    } finally {
      _suspensions--;
      _graceUntil = _now().add(grace);
    }
  }

  /// For something the app opens without waiting on it: the next trip to
  /// the background, if it starts within [grace], doesn't lock.
  void pauseLocking() => _graceUntil = _now().add(grace);

  /// Called by the gate on every app lifecycle change.
  void handleLifecycle(AppLifecycleState lifecycle) {
    switch (lifecycle) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // Leaving goes hidden then paused; coming back goes through hidden
        // again. Only the first one starts the trip.
        if (_backgroundSince != null) return;
        _backgroundSince = _now();
        _excused = _suspended;
        if (!_excused && _guarding && state.delay == LockDelay.immediately) {
          // Lock on the way out, so the recent-apps preview is likelier to
          // show the lock screen rather than the conversation.
          _lock();
        }
      case AppLifecycleState.resumed:
        final since = _backgroundSince;
        final excused = _excused;
        _backgroundSince = null;
        _excused = false;
        if (since == null || excused || !_guarding) return;
        if (state.locked) {
          // Back while still locked: offer the prompt again, unless it is
          // still up.
          if (state.authenticating) return;
          state = state.copyWith(lockCount: state.lockCount + 1);
        } else if (_now().difference(since) >= state.delay.duration) {
          _lock();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Called by the gate when someone signs in or out. Signing out unlocks,
  /// so the next person to sign in isn't met by the lock; it comes back on
  /// the next cold start or trip to the background.
  void setSignedIn(bool signedIn) {
    _signedOut = !signedIn;
    if (!signedIn && state.locked) {
      state = state.copyWith(locked: false, failed: false);
    }
  }

  void _lock() {
    state = state.copyWith(
      locked: true,
      failed: false,
      lockCount: state.lockCount + 1,
    );
  }

  /// Shows the system prompt and unlocks on success. On failure or cancel
  /// the app stays locked and [AppLockState.failed] is set.
  Future<bool> unlock() async {
    if (!state.locked) return true;
    if (state.authenticating) return false;
    state = state.copyWith(authenticating: true, failed: false);
    final auth = ref.read(biometricAuthProvider);
    final ok = await suspendWhile(auth.authenticate('Unlock Us'));
    if (!ref.mounted) return ok;
    state = state.copyWith(
      authenticating: false,
      locked: ok ? false : state.locked,
      failed: !ok,
    );
    return ok;
  }

  /// Turns the lock on or off. Turning it on first asks the user to prove
  /// it's them, so a phone where that can't work never gets locked; returns
  /// false (and changes nothing) if they don't.
  Future<bool> setEnabled(bool enabled) async {
    if (enabled == state.enabled) return true;
    if (enabled) {
      final auth = ref.read(biometricAuthProvider);
      final ok = await suspendWhile(
        auth.authenticate('Confirm it\'s you to turn on app lock'),
      );
      if (!ok || !ref.mounted) return false;
    }
    await _settings.setEnabled(enabled);
    if (!ref.mounted) return true;
    // Turning it on doesn't lock now; turning it off clears any lock.
    state = state.copyWith(enabled: enabled, locked: false, failed: false);
    return true;
  }

  Future<void> setDelay(LockDelay delay) async {
    await _settings.setDelay(delay);
    if (!ref.mounted) return;
    state = state.copyWith(delay: delay);
  }
}

/// The app lock for this phone.
final appLockControllerProvider =
    NotifierProvider<AppLockController, AppLockState>(AppLockController.new);
