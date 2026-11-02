import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Android "Ongoing call" notification (OngoingCallService.kt).
///
/// While it shows, Android keeps the app running with the microphone (and
/// camera) in use, so a call carries on when someone leaves the app, locks
/// the phone or switches to another app.
class OngoingCallNotification {
  const OngoingCallNotification();

  /// The app-wide instance; tests swap in a fake.
  static OngoingCallNotification instance = const OngoingCallNotification();

  static const _channel = MethodChannel('us/ongoing_call');

  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Shows the notification. Returns false if Android refused.
  Future<bool> start({required String partnerName, required bool video}) async {
    if (!_android) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('start', {
        'title': partnerName,
        'text': video
            ? 'Ongoing video call · tap to return'
            : 'Ongoing voice call · tap to return',
        'video': video,
      });
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> stop() async {
    if (!_android) return;
    try {
      await _channel.invokeMethod<bool>('stop');
    } on MissingPluginException {
      // Not on a phone build (tests).
    } on PlatformException {
      // Nothing to stop.
    }
  }
}
