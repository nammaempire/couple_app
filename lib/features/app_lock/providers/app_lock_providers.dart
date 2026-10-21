import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/app_lock/data/app_lock_settings.dart';
import 'package:couple_app/features/app_lock/data/biometric_auth.dart';

/// The phone's fingerprint, face or screen-lock prompt.
final biometricAuthProvider = Provider<BiometricAuth>(
  (ref) => LocalBiometricAuth(),
);

/// This phone's app-lock settings. `main` overrides it with the stored
/// settings, loaded before the first frame; the default keeps the lock off,
/// so tests and previews never touch a platform channel.
final appLockSettingsProvider = Provider<AppLockSettings>(
  (ref) => MemoryAppLockSettings(),
);

/// The time, for the lock delay. Tests replace it with a fake clock.
final appLockClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
