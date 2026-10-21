import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Tells the app when the user takes a screenshot.
///
/// Behind an interface so tests can fake it.
abstract class ScreenshotDetector {
  /// One event per screenshot, while started.
  Stream<void> get screenshots;

  /// Starts listening. Harmless to call when already started.
  Future<void> start();

  Future<void> stop();
}

/// Turns the system's secure-window mode on and off. While it is on,
/// screenshots and screen recordings come out black and the recent-apps
/// preview is hidden.
abstract class ScreenSecurity {
  Future<void> setSecure(bool secure);
}

/// Both, through the app's own `couple_app/screen_privacy` channel (see
/// `ScreenPrivacy.kt` in the Android project).
///
/// Detection uses `Activity.registerScreenCaptureCallback`, so it works on
/// Android 14 (API 34) and newer; it needs only the install-time
/// `DETECT_SCREEN_CAPTURE` permission, not access to the user's photos.
/// Older phones simply never report a screenshot. Secure mode is the
/// window's `FLAG_SECURE`, which works on every version.
class PlatformScreenPrivacy implements ScreenshotDetector, ScreenSecurity {
  PlatformScreenPrivacy._();

  static final instance = PlatformScreenPrivacy._();

  static const _channel = MethodChannel('couple_app/screen_privacy');

  final _screenshots = StreamController<void>.broadcast();
  bool _handlerSet = false;

  @override
  Stream<void> get screenshots => _screenshots.stream;

  void _ensureHandler() {
    if (_handlerSet) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onScreenshot') _screenshots.add(null);
    });
  }

  @override
  Future<void> start() async {
    _ensureHandler();
    await _invoke('startDetection');
  }

  @override
  Future<void> stop() => _invoke('stopDetection');

  @override
  Future<void> setSecure(bool secure) =>
      _invoke('setSecure', {'secure': secure});

  /// Best effort: missing on other platforms and in tests.
  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Not Android, or no host app (tests).
    } on PlatformException catch (e) {
      debugPrint('screen_privacy.$method failed: ${e.message}');
    }
  }
}

/// Coordinates screenshot detection and blocking for the screens that show
/// the conversation.
///
/// Each such screen holds a claim while it is on screen. While any claim
/// is held, screenshots are detected and reported to the newest claim (the
/// screen on top), at most once per [debounce]; secure mode is on while any
/// claim asks for it. With no claims, detection stops and secure mode is
/// switched off, so the rest of the app behaves normally.
class ScreenPrivacyGuard {
  ScreenPrivacyGuard({
    required this._detector,
    required this._security,
    this.debounce = const Duration(seconds: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ScreenshotDetector _detector;
  final ScreenSecurity _security;
  final Duration debounce;
  final DateTime Function() _now;

  /// Holders in the order they claimed, newest last.
  final _claims = <Object, _Claim>{};
  StreamSubscription<void>? _subscription;
  bool _secure = false;
  DateTime? _lastReported;

  /// Whether some screen currently holds a claim.
  bool get isWatching => _claims.isNotEmpty;

  /// Adds or updates [holder]'s claim. [secure] asks for secure mode;
  /// [onScreenshot] runs when a screenshot is reported to this holder.
  void claim(
    Object holder, {
    required bool secure,
    required VoidCallback onScreenshot,
  }) {
    final existing = _claims[holder];
    if (existing != null) {
      existing
        ..secure = secure
        ..onScreenshot = onScreenshot;
    } else {
      _claims[holder] = _Claim(secure: secure, onScreenshot: onScreenshot);
    }
    _apply();
  }

  void release(Object holder) {
    if (_claims.remove(holder) == null) return;
    _apply();
  }

  void _apply() {
    final secure = _claims.values.any((c) => c.secure);
    if (secure != _secure) {
      _secure = secure;
      _security.setSecure(secure);
    }

    if (_claims.isNotEmpty && _subscription == null) {
      _subscription = _detector.screenshots.listen((_) => _onScreenshot());
      _detector.start();
    } else if (_claims.isEmpty && _subscription != null) {
      _subscription!.cancel();
      _subscription = null;
      _detector.stop();
    }
  }

  void _onScreenshot() {
    if (_claims.isEmpty) return;
    final now = _now();
    final last = _lastReported;
    if (last != null && now.difference(last) < debounce) return;
    _lastReported = now;
    _claims.values.last.onScreenshot();
  }

  void dispose() {
    _claims.clear();
    _apply();
  }
}

class _Claim {
  _Claim({required this.secure, required this.onScreenshot});

  bool secure;
  VoidCallback onScreenshot;
}
