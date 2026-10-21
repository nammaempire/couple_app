import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// The phone's own lock: fingerprint, face, or the screen-lock PIN,
/// pattern or password as a fallback.
///
/// Behind an interface so tests can fake it.
abstract class BiometricAuth {
  /// Whether this phone has a fingerprint, face or screen lock set up, so
  /// [authenticate] can succeed at all.
  Future<bool> canAuthenticate();

  /// Shows the system prompt with [reason]. True only when the user proved
  /// it's them; false when they cancel, fail or the prompt can't be shown.
  Future<bool> authenticate(String reason);
}

/// [BiometricAuth] through the local_auth plugin.
///
/// Never throws: every plugin error counts as "can't" or "didn't".
class LocalBiometricAuth implements BiometricAuth {
  LocalBiometricAuth([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> canAuthenticate() async {
    try {
      // True when a screen lock is set or a biometric is enrolled.
      return await _auth.isDeviceSupported();
    } catch (e) {
      debugPrint('local_auth.isDeviceSupported failed: $e');
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // Lets the phone's PIN, pattern or password stand in for biometrics.
        biometricOnly: false,
        // Face unlock goes straight through, without an extra confirm tap.
        sensitiveTransaction: false,
      );
    } on LocalAuthException catch (e) {
      debugPrint('local_auth.authenticate: ${e.code.name} ${e.description}');
      return false;
    } catch (e) {
      debugPrint('local_auth.authenticate failed: $e');
      return false;
    }
  }
}
