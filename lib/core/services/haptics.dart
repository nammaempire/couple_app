import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A real phone vibration (Haptics.kt), for things from the partner that
/// arrive while the app is open. Falls back to Flutter's light haptic tick
/// where the native side isn't there (tests, other platforms).
class Haptics {
  const Haptics._();

  static const _channel = MethodChannel('us/haptics');

  /// A soft double buzz, like a heartbeat.
  static const heartbeat = [0, 120, 90, 160];

  static Future<void> buzz([List<int> pattern = heartbeat]) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final ok = await _channel.invokeMethod<bool>('buzz', {
          'pattern': pattern,
        });
        if (ok ?? false) return;
      } on MissingPluginException {
        // Fall through to the haptic tick.
      } on PlatformException {
        // Fall through to the haptic tick.
      }
    }
    await HapticFeedback.heavyImpact();
  }
}
