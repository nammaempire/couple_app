import 'package:shared_preferences/shared_preferences.dart';

/// How long the app may sit in the background before it locks.
enum LockDelay {
  immediately(Duration.zero, 'Immediately'),
  oneMinute(Duration(minutes: 1), 'After 1 minute'),
  fiveMinutes(Duration(minutes: 5), 'After 5 minutes'),
  fifteenMinutes(Duration(minutes: 15), 'After 15 minutes');

  const LockDelay(this.duration, this.label);

  final Duration duration;
  final String label;

  static const fallback = LockDelay.oneMinute;

  static LockDelay fromName(String? name) => LockDelay.values.firstWhere(
    (d) => d.name == name,
    orElse: () => fallback,
  );
}

/// The app-lock choices for this phone. They are kept on the device, not in
/// the user's profile, so each phone decides for itself.
///
/// Reads are synchronous so the lock can be decided before the first frame.
abstract class AppLockSettings {
  bool get enabled;
  LockDelay get delay;

  Future<void> setEnabled(bool enabled);
  Future<void> setDelay(LockDelay delay);
}

/// [AppLockSettings] kept in memory only: off by default. Used until the
/// stored settings are loaded at start-up, and in tests.
class MemoryAppLockSettings implements AppLockSettings {
  MemoryAppLockSettings({
    this.enabled = false,
    this.delay = LockDelay.fallback,
  });

  @override
  bool enabled;

  @override
  LockDelay delay;

  @override
  Future<void> setEnabled(bool enabled) async => this.enabled = enabled;

  @override
  Future<void> setDelay(LockDelay delay) async => this.delay = delay;
}

/// [AppLockSettings] stored with shared_preferences.
class PrefsAppLockSettings implements AppLockSettings {
  PrefsAppLockSettings(this._prefs);

  static const enabledKey = 'appLock.enabled';
  static const delayKey = 'appLock.delay';

  final SharedPreferences _prefs;

  /// Loads the stored settings. Falls back to [MemoryAppLockSettings] (lock
  /// off) if the store can't be opened, so start-up never fails over it.
  static Future<AppLockSettings> load() async {
    try {
      return PrefsAppLockSettings(await SharedPreferences.getInstance());
    } catch (_) {
      return MemoryAppLockSettings();
    }
  }

  @override
  bool get enabled => _prefs.getBool(enabledKey) ?? false;

  @override
  LockDelay get delay => LockDelay.fromName(_prefs.getString(delayKey));

  @override
  Future<void> setEnabled(bool enabled) => _prefs.setBool(enabledKey, enabled);

  @override
  Future<void> setDelay(LockDelay delay) =>
      _prefs.setString(delayKey, delay.name);
}
