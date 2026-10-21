import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:couple_app/core/theme/app_theme.dart';
import 'package:couple_app/features/app_lock/app_lock_controller.dart';
import 'package:couple_app/features/app_lock/data/app_lock_settings.dart';
import 'package:couple_app/features/app_lock/data/biometric_auth.dart';
import 'package:couple_app/features/app_lock/providers/app_lock_providers.dart';
import 'package:couple_app/features/app_lock/widgets/app_lock_gate.dart';
import 'package:couple_app/features/app_lock/widgets/app_lock_settings_sheet.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';

const me = 'asha';

/// Answers the system prompt with [result] and records each reason.
class _FakeBiometrics implements BiometricAuth {
  bool available = true;
  bool result = true;
  final reasons = <String>[];

  /// When set, [authenticate] waits for it instead of answering at once.
  Completer<bool>? pending;

  @override
  Future<bool> canAuthenticate() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    reasons.add(reason);
    final wait = pending;
    if (wait != null) return wait.future;
    return result;
  }
}

/// Only the uid is used.
class _FakeUser implements User {
  @override
  String get uid => me;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A clock the tests move by hand.
class _Clock {
  DateTime now = DateTime(2026, 10, 17, 12);

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}

/// Leaving the app: inactive, hidden then paused.
void _leave(AppLockController lock) {
  lock
    ..handleLifecycle(AppLifecycleState.inactive)
    ..handleLifecycle(AppLifecycleState.hidden)
    ..handleLifecycle(AppLifecycleState.paused);
}

/// Coming back: hidden, inactive then resumed.
void _comeBack(AppLockController lock) {
  lock
    ..handleLifecycle(AppLifecycleState.hidden)
    ..handleLifecycle(AppLifecycleState.inactive)
    ..handleLifecycle(AppLifecycleState.resumed);
}

/// Drives the real lifecycle channel, as the engine does.
Future<void> _setLifecycle(AppLifecycleState state) async {
  final message = const StringCodec().encodeMessage(state.toString());
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('flutter/lifecycle', message, (_) {});
}

void main() {
  late _Clock clock;
  late _FakeBiometrics biometrics;

  setUp(() {
    clock = _Clock();
    biometrics = _FakeBiometrics();
  });

  ProviderContainer container(AppLockSettings settings) {
    return ProviderContainer.test(
      overrides: [
        appLockSettingsProvider.overrideWithValue(settings),
        biometricAuthProvider.overrideWithValue(biometrics),
        appLockClockProvider.overrideWithValue(clock.call),
      ],
    );
  }

  /// An enabled lock, already unlocked once after the cold start.
  Future<(ProviderContainer, AppLockController)> unlocked({
    LockDelay delay = LockDelay.oneMinute,
  }) async {
    final c = container(MemoryAppLockSettings(enabled: true, delay: delay));
    final lock = c.read(appLockControllerProvider.notifier);
    expect(await lock.unlock(), isTrue);
    // Past the grace period that follows the unlock prompt.
    clock.advance(const Duration(seconds: 10));
    return (c, lock);
  }

  group('LockDelay and settings', () {
    test(
      'defaults to off, after 1 minute; stores choices on the device',
      () async {
        SharedPreferences.setMockInitialValues({});
        final settings = await PrefsAppLockSettings.load();
        expect(settings.enabled, isFalse);
        expect(settings.delay, LockDelay.oneMinute);

        await settings.setEnabled(true);
        await settings.setDelay(LockDelay.fifteenMinutes);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(PrefsAppLockSettings.enabledKey), isTrue);
        expect(
          prefs.getString(PrefsAppLockSettings.delayKey),
          'fifteenMinutes',
        );
        expect(LockDelay.fromName('nonsense'), LockDelay.oneMinute);
        expect(LockDelay.values.map((d) => d.label), [
          'Immediately',
          'After 1 minute',
          'After 5 minutes',
          'After 15 minutes',
        ]);
      },
    );
  });

  group('AppLockController', () {
    test('locks on a cold start when enabled, not when off', () async {
      SharedPreferences.setMockInitialValues({
        PrefsAppLockSettings.enabledKey: true,
      });
      final on = container(await PrefsAppLockSettings.load());
      expect(on.read(appLockControllerProvider).locked, isTrue);
      expect(on.read(appLockControllerProvider).lockCount, 1);

      final off = container(MemoryAppLockSettings());
      expect(off.read(appLockControllerProvider).locked, isFalse);
    });

    test('locks only after the chosen delay in the background', () async {
      final (c, lock) = await unlocked();

      _leave(lock);
      clock.advance(const Duration(seconds: 59));
      _comeBack(lock);
      expect(c.read(appLockControllerProvider).locked, isFalse);

      _leave(lock);
      clock.advance(const Duration(minutes: 1));
      _comeBack(lock);
      expect(c.read(appLockControllerProvider).locked, isTrue);
    });

    test('a short pause without hiding (inactive) never locks', () async {
      final (c, lock) = await unlocked(delay: LockDelay.immediately);
      lock.handleLifecycle(AppLifecycleState.inactive);
      clock.advance(const Duration(hours: 1));
      lock.handleLifecycle(AppLifecycleState.resumed);
      expect(c.read(appLockControllerProvider).locked, isFalse);
    });

    test('"Immediately" locks on the way out', () async {
      final (c, lock) = await unlocked(delay: LockDelay.immediately);
      lock.handleLifecycle(AppLifecycleState.inactive);
      expect(c.read(appLockControllerProvider).locked, isFalse);
      lock.handleLifecycle(AppLifecycleState.hidden);
      expect(c.read(appLockControllerProvider).locked, isTrue);
      final count = c.read(appLockControllerProvider).lockCount;

      lock
        ..handleLifecycle(AppLifecycleState.paused)
        ..handleLifecycle(AppLifecycleState.hidden)
        ..handleLifecycle(AppLifecycleState.inactive)
        ..handleLifecycle(AppLifecycleState.resumed);
      // Still locked, and the lock screen is asked to prompt again.
      expect(c.read(appLockControllerProvider).locked, isTrue);
      expect(c.read(appLockControllerProvider).lockCount, count + 1);
    });

    test('suspendWhile keeps a picker trip from locking', () async {
      final (c, lock) = await unlocked(delay: LockDelay.immediately);

      final picker = Completer<String?>();
      final picked = lock.suspendWhile(picker.future);
      _leave(lock);
      expect(c.read(appLockControllerProvider).locked, isFalse);
      clock.advance(const Duration(minutes: 20));
      // The result may arrive before or after the resume event.
      picker.complete('photo.jpg');
      expect(await picked, 'photo.jpg');
      _comeBack(lock);
      expect(c.read(appLockControllerProvider).locked, isFalse);

      // The next, ordinary trip locks again.
      clock.advance(const Duration(seconds: 10));
      _leave(lock);
      _comeBack(lock);
      expect(c.read(appLockControllerProvider).locked, isTrue);
    });

    test('a launch that returns before the app is hidden is covered by the '
        'grace period', () async {
      final (c, lock) = await unlocked(delay: LockDelay.immediately);

      // url_launcher reports success before Spotify is in front.
      expect(await lock.suspendWhile(Future.value(true)), isTrue);
      clock.advance(const Duration(seconds: 1));
      _leave(lock);
      clock.advance(const Duration(minutes: 5));
      _comeBack(lock);
      expect(c.read(appLockControllerProvider).locked, isFalse);

      lock.pauseLocking();
      clock.advance(const Duration(seconds: 2));
      _leave(lock);
      _comeBack(lock);
      expect(c.read(appLockControllerProvider).locked, isFalse);

      // Once the grace period is over, leaving locks as usual.
      lock.pauseLocking();
      clock.advance(AppLockController.grace + const Duration(seconds: 1));
      _leave(lock);
      _comeBack(lock);
      expect(c.read(appLockControllerProvider).locked, isTrue);
    });

    test('unlock: success unlocks, failure stays locked', () async {
      final c = container(MemoryAppLockSettings(enabled: true));
      final lock = c.read(appLockControllerProvider.notifier);

      biometrics.result = false;
      expect(await lock.unlock(), isFalse);
      var state = c.read(appLockControllerProvider);
      expect(state.locked, isTrue);
      expect(state.failed, isTrue);
      expect(state.authenticating, isFalse);

      biometrics.result = true;
      expect(await lock.unlock(), isTrue);
      state = c.read(appLockControllerProvider);
      expect(state.locked, isFalse);
      expect(state.failed, isFalse);
      expect(biometrics.reasons, ['Unlock Us', 'Unlock Us']);
    });

    test('the unlock prompt itself does not lock again', () async {
      final c = container(
        MemoryAppLockSettings(enabled: true, delay: LockDelay.immediately),
      );
      final lock = c.read(appLockControllerProvider.notifier);
      biometrics.pending = Completer<bool>();
      final unlocking = lock.unlock();
      expect(c.read(appLockControllerProvider).authenticating, isTrue);
      // The PIN screen is its own activity on some phones.
      _leave(lock);
      _comeBack(lock);
      biometrics.pending!.complete(true);
      expect(await unlocking, isTrue);
      expect(c.read(appLockControllerProvider).locked, isFalse);
    });

    test('turning it on needs a successful check first', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await PrefsAppLockSettings.load();
      final c = container(settings);
      final lock = c.read(appLockControllerProvider.notifier);

      biometrics.result = false;
      expect(await lock.setEnabled(true), isFalse);
      expect(c.read(appLockControllerProvider).enabled, isFalse);
      expect(settings.enabled, isFalse);

      biometrics.result = true;
      expect(await lock.setEnabled(true), isTrue);
      final state = c.read(appLockControllerProvider);
      expect(state.enabled, isTrue);
      expect(state.locked, isFalse);
      expect(settings.enabled, isTrue);
      expect(biometrics.reasons, hasLength(2));

      await lock.setDelay(LockDelay.fiveMinutes);
      expect(settings.delay, LockDelay.fiveMinutes);

      // Turning it off asks nothing.
      expect(await lock.setEnabled(false), isTrue);
      expect(settings.enabled, isFalse);
      expect(biometrics.reasons, hasLength(2));
    });

    test('signed out: unlocked, and the background never locks', () async {
      final c = container(
        MemoryAppLockSettings(enabled: true, delay: LockDelay.immediately),
      );
      final lock = c.read(appLockControllerProvider.notifier);
      expect(c.read(appLockControllerProvider).locked, isTrue);

      lock.setSignedIn(false);
      expect(c.read(appLockControllerProvider).locked, isFalse);
      _leave(lock);
      clock.advance(const Duration(hours: 1));
      _comeBack(lock);
      expect(c.read(appLockControllerProvider).locked, isFalse);

      // Signing in doesn't lock; the next trip away does.
      lock.setSignedIn(true);
      expect(c.read(appLockControllerProvider).locked, isFalse);
      _leave(lock);
      _comeBack(lock);
      expect(c.read(appLockControllerProvider).locked, isTrue);
    });
  });

  group('App lock sheet', () {
    Future<ProviderContainer> pumpSheet(
      WidgetTester tester, {
      AppLockSettings? settings,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appLockSettingsProvider.overrideWithValue(
              settings ?? MemoryAppLockSettings(),
            ),
            biometricAuthProvider.overrideWithValue(biometrics),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showAppLockSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.text('open')));
    }

    SwitchListTile lockSwitch(WidgetTester tester) =>
        tester.widget<SwitchListTile>(find.byType(SwitchListTile));

    testWidgets('the switch is disabled with a reason when the phone has no '
        'lock', (tester) async {
      biometrics.available = false;
      await pumpSheet(tester);
      expect(find.text(appLockUnavailableText), findsOneWidget);
      expect(lockSwitch(tester).onChanged, isNull);
      expect(biometrics.reasons, isEmpty);
    });

    testWidgets('it stays switchable off when the phone lock was removed', (
      tester,
    ) async {
      biometrics.available = false;
      await pumpSheet(tester, settings: MemoryAppLockSettings(enabled: true));
      expect(lockSwitch(tester).onChanged, isNotNull);
    });

    testWidgets('turning it on asks first; a failed check keeps it off', (
      tester,
    ) async {
      final c = await pumpSheet(tester);
      expect(lockSwitch(tester).onChanged, isNotNull);
      // Delays wait until the lock is on.
      expect(
        tester
            .widget<RadioListTile<LockDelay>>(
              find.widgetWithText(RadioListTile<LockDelay>, 'Immediately'),
            )
            .enabled,
        isFalse,
      );

      biometrics.result = false;
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(c.read(appLockControllerProvider).enabled, isFalse);
      expect(find.textContaining('app lock is off'), findsOneWidget);

      biometrics.result = true;
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(c.read(appLockControllerProvider).enabled, isTrue);
      expect(lockSwitch(tester).value, isTrue);

      await tester.tap(find.text('After 15 minutes'));
      await tester.pumpAndSettle();
      expect(c.read(appLockControllerProvider).delay, LockDelay.fifteenMinutes);
    });
  });

  group('AppLockGate', () {
    late StreamController<User?> auth;
    late int contentTaps;

    setUp(() {
      auth = StreamController<User?>.broadcast();
      contentTaps = 0;
    });

    tearDown(() => auth.close());

    List<Override> overrides(AppLockSettings settings) => [
      appLockSettingsProvider.overrideWithValue(settings),
      biometricAuthProvider.overrideWithValue(biometrics),
      appLockClockProvider.overrideWithValue(clock.call),
      authStateProvider.overrideWith((ref) => auth.stream),
      profileProvider(me).overrideWith(
        (ref) => Stream.value(
          const AppUser(uid: me, displayName: 'Asha', coupleId: 'c1'),
        ),
      ),
      partnerProvider.overrideWith(
        (ref) => Stream.value(const AppUser(uid: 'ravi', displayName: 'Ravi')),
      ),
    ];

    Future<void> pumpApp(WidgetTester tester, AppLockSettings settings) async {
      addTearDown(() => _setLifecycle(AppLifecycleState.resumed));
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(settings),
          child: AppLockGate(
            child: MaterialApp(
              theme: AppTheme.light(),
              builder: (context, child) => AppLockOverlay(child: child!),
              home: Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => contentTaps++,
                    child: const Text('Our secret chat'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('covers the app on a cold start, prompts once, and the '
        'Unlock button tries again', (tester) async {
      biometrics.result = false;
      await pumpApp(tester, MemoryAppLockSettings(enabled: true));
      auth.add(_FakeUser());
      await tester.pumpAndSettle();

      expect(find.text('Us is locked'), findsOneWidget);
      // Prompted by itself once; cancelled.
      expect(biometrics.reasons, ['Unlock Us']);
      expect(find.text('That didn\'t work. Try again.'), findsOneWidget);

      // The app is underneath but can't be reached.
      await tester.tap(find.text('Our secret chat'), warnIfMissed: false);
      expect(contentTaps, 0);

      biometrics.result = true;
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(biometrics.reasons, hasLength(2));
      expect(find.text('Us is locked'), findsNothing);
      await tester.tap(find.text('Our secret chat'));
      expect(contentTaps, 1);
    });

    testWidgets('back does not pop the screens behind the lock', (
      tester,
    ) async {
      biometrics.result = false;
      await pumpApp(tester, MemoryAppLockSettings(enabled: true));
      auth.add(_FakeUser());
      await tester.pumpAndSettle();
      expect(find.text('Us is locked'), findsOneWidget);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const Text('Call screen')),
      );
      await tester.pumpAndSettle();
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      // Still there, and still locked.
      expect(find.text('Call screen', skipOffstage: false), findsOneWidget);
      expect(find.text('Us is locked'), findsOneWidget);
    });

    testWidgets('locks again after the delay in the background', (
      tester,
    ) async {
      await pumpApp(
        tester,
        MemoryAppLockSettings(enabled: true, delay: LockDelay.fiveMinutes),
      );
      auth.add(_FakeUser());
      await tester.pumpAndSettle();
      // Unlocked by the automatic prompt.
      expect(find.text('Us is locked'), findsNothing);
      clock.advance(const Duration(seconds: 10));

      await _setLifecycle(AppLifecycleState.paused);
      clock.advance(const Duration(minutes: 6));
      biometrics.result = false;
      await _setLifecycle(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Us is locked'), findsOneWidget);
      expect(biometrics.reasons, hasLength(2));
    });

    testWidgets('never shows while signed out', (tester) async {
      await pumpApp(
        tester,
        MemoryAppLockSettings(enabled: true, delay: LockDelay.immediately),
      );
      auth.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Us is locked'), findsNothing);
      expect(find.text('Our secret chat'), findsOneWidget);

      await _setLifecycle(AppLifecycleState.paused);
      await _setLifecycle(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Us is locked'), findsNothing);

      // Signing in afterwards isn't met by the lock either.
      auth.add(_FakeUser());
      await tester.pumpAndSettle();
      expect(find.text('Us is locked'), findsNothing);
      expect(biometrics.reasons, isEmpty);
    });

    testWidgets('off by default: no lock and no platform calls', (
      tester,
    ) async {
      await pumpApp(tester, MemoryAppLockSettings());
      auth.add(_FakeUser());
      await _setLifecycle(AppLifecycleState.paused);
      clock.advance(const Duration(hours: 1));
      await _setLifecycle(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Us is locked'), findsNothing);
      expect(biometrics.reasons, isEmpty);
    });
  });
}
