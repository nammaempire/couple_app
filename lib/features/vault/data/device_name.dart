import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The phone's model, e.g. "Pixel 8", shown when approving it.
///
/// Behind an interface so tests can name phones.
abstract class DeviceNameSource {
  Future<String> deviceName();
}

/// [DeviceNameSource] through the app's `couple_app/device_info` channel
/// (see `MainActivity.kt`). Falls back to "Android phone".
class PlatformDeviceName implements DeviceNameSource {
  const PlatformDeviceName();

  static const _channel = MethodChannel('couple_app/device_info');
  static const fallback = 'Android phone';

  @override
  Future<String> deviceName() async {
    try {
      final name = await _channel.invokeMethod<String>('deviceName');
      return (name == null || name.trim().isEmpty) ? fallback : name.trim();
    } on MissingPluginException {
      return fallback;
    } on PlatformException catch (e) {
      debugPrint('device_info.deviceName failed: ${e.message}');
      return fallback;
    }
  }
}
