import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:couple_app/features/together/data/reminder_planner.dart';

/// Schedules [PlannedReminder]s as local notifications on this device.
///
/// Each phone schedules its own, from the events and notes it can see, so
/// reminders work without a push server. They are re-synced whenever those
/// change and each time the app starts.
class ReminderService {
  ReminderService._();

  static final ReminderService instance = ReminderService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _init;
  bool _askedPermission = false;

  /// Syncs and clears run one after another, so an older plan that was
  /// waiting on the permission dialog can never overwrite a newer one.
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Upcoming dates, events and love notes',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<bool> _ensureInitialised() {
    return _init ??= () async {
      try {
        tzdata.initializeTimeZones();
        try {
          final local = await FlutterTimezone.getLocalTimezone();
          tz.setLocalLocation(tz.getLocation(local.identifier));
        } catch (_) {
          // Unknown zone name: fall back to UTC offsets via tz.local.
        }
        await _plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          ),
        );
        return true;
      } catch (_) {
        return false;
      }
    }();
  }

  /// Replaces every scheduled reminder with [reminders]. Returns false if
  /// the platform could not be reached, so the caller can retry later.
  Future<bool> sync(List<PlannedReminder> reminders) {
    return _serial(() async {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        return true;
      }
      if (!await _ensureInitialised()) return false;

      if (reminders.isNotEmpty && !_askedPermission) {
        _askedPermission = true;
        try {
          await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission();
        } catch (_) {}
      }

      try {
        await _plugin.cancelAllPendingNotifications();
      } catch (_) {
        return false;
      }

      // Checked now, after any permission dialog: a reminder that became due
      // while it was open is skipped rather than rejected.
      final earliest = DateTime.now().add(const Duration(seconds: 30));
      for (final r in reminders) {
        if (!r.at.isAfter(earliest)) continue;
        try {
          await _plugin.zonedSchedule(
            id: r.id,
            scheduledDate: tz.TZDateTime.from(r.at, tz.local),
            notificationDetails: _details,
            // Inexact: no exact-alarm permission needed; may be a few
            // minutes late, which is fine for reminders.
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            title: r.title,
            body: r.body,
          );
        } catch (_) {
          // One bad reminder must not stop the rest.
        }
      }
      return true;
    });
  }

  /// Clears everything, e.g. on sign-out. Queued behind any sync in flight,
  /// so nothing is rescheduled after it.
  Future<void> clear() {
    return _serial(() async {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
      if (!await _ensureInitialised()) return;
      try {
        await _plugin.cancelAllPendingNotifications();
      } catch (_) {}
    });
  }
}
