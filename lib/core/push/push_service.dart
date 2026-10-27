import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import 'package:couple_app/core/backend/backend.dart';

/// Push notifications: makes the phone buzz for love taps, messages, calls,
/// mood, notes and the daily question even when the app is closed.
///
/// The Us server decides who to notify and sends the alert through Firebase
/// Cloud Messaging. This class only:
///  - creates the Android notification channels (each with its own sound
///    and importance, which people can change in Android settings),
///  - asks for notification permission (Android 13+),
///  - saves this phone's push token at `users/{uid}/pushTokens/{id}`, with
///    its time zone so quiet hours follow the phone, and removes it on
///    sign-out.
///
/// While the app is open, alerts are not shown as notifications: the app
/// already shows love taps, messages and calls on screen.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  String? _uid;
  String? _token;
  StreamSubscription<String>? _refreshSub;
  Future<void>? _channels;

  /// Push needs Firebase and Android; tests and other platforms skip it.
  bool get _available =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      Firebase.apps.isNotEmpty;

  /// Notification channels. Their ids must match the server
  /// (server/src/push/triggers.ts).
  static const _channelList = <AndroidNotificationChannel>[
    AndroidNotificationChannel(
      'love',
      'Love taps',
      description: 'Thinking of you, hugs, kisses and more',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      'messages',
      'Messages',
      description: 'New chat messages and love notes',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      'calls',
      'Calls',
      description: 'Incoming voice and video calls',
      importance: Importance.max,
    ),
    AndroidNotificationChannel(
      'updates',
      'Moods and questions',
      description: 'Mood changes, love notes and the daily question',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      'quiet',
      'Quiet hours',
      description: 'Alerts that arrive silently during quiet hours',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    ),
  ];

  Future<void> _ensureChannels() {
    return _channels ??= () async {
      final android = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) return;
      for (final channel in _channelList) {
        await android.createNotificationChannel(channel);
      }
    }();
  }

  /// Registers this phone for [uid]'s notifications. Safe to call often.
  Future<void> start(String uid) async {
    if (!_available) return;
    try {
      await _ensureChannels();
      if (_uid == uid && _token != null) return;
      _uid = uid;

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      // While the app is open, the app's own banners show the event.
      await messaging.setForegroundNotificationPresentationOptions();

      final token = await messaging.getToken();
      if (token != null) await _save(uid, token);

      await _refreshSub?.cancel();
      _refreshSub = messaging.onTokenRefresh.listen((t) {
        final current = _uid;
        if (current != null) unawaited(_save(current, t));
      });
    } catch (e) {
      debugPrint('Push notifications not available: $e');
    }
  }

  /// Unregisters this phone (call before signing out).
  Future<void> stop() async {
    if (!_available) return;
    final uid = _uid;
    final token = _token;
    _uid = null;
    _token = null;
    await _refreshSub?.cancel();
    _refreshSub = null;
    try {
      if (uid != null && token != null) {
        await Db.instance
            .doc('users/$uid/pushTokens/${tokenId(token)}')
            .delete()
            .timeout(const Duration(seconds: 5));
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // Offline: the server drops tokens FCM reports as dead.
    }
  }

  Future<void> _save(String uid, String token) async {
    final old = _token;
    _token = token;
    String? zone;
    try {
      zone = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      zone = null;
    }
    await Db.instance.doc('users/$uid/pushTokens/${tokenId(token)}').set({
      'token': token,
      'platform': 'android',
      'timeZone': zone,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (old != null && old != token) {
      try {
        await Db.instance.doc('users/$uid/pushTokens/${tokenId(old)}').delete();
      } catch (_) {}
    }
  }

  /// A short, stable document id for a token (FNV-1a, 64 bits as hex).
  @visibleForTesting
  static String tokenId(String token) {
    var h1 = 0x811c9dc5;
    var h2 = 0x01000193;
    for (final unit in token.codeUnits) {
      h1 = ((h1 ^ unit) * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 ^ unit) * 0x811c9dc5) & 0xFFFFFFFF;
    }
    return 'p${h1.toRadixString(16).padLeft(8, '0')}'
        '${h2.toRadixString(16).padLeft(8, '0')}';
  }
}
