package com.nammaempire.together

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Keeps a voice or video call alive while the app is in the background.
 *
 * Android only lets an app keep using the microphone and camera after it
 * leaves the screen while a foreground service is running, and phones with
 * aggressive battery savers (Realme, OnePlus, Xiaomi…) close background
 * apps without one. This service shows the "Ongoing call" notification
 * (tapping it returns to the app) and does nothing else: the call itself
 * stays in the Flutter code.
 *
 * Started from Dart over the "us/ongoing_call" channel once a call has
 * connected (so the microphone/camera permissions are already granted), and
 * stopped when it ends.
 */
class OngoingCallService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Ongoing call"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Tap to return to the call"
        val video = intent?.getBooleanExtra(EXTRA_VIDEO, false) ?: false
        val notification = buildNotification(title, text)
        if (!startInForeground(notification, video)) {
            stopSelf()
        }
        return START_NOT_STICKY
    }

    /** Swiping the app away ends the call, so the notification goes too. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    private fun startInForeground(notification: Notification, video: Boolean): Boolean {
        // Microphone/camera service types (and the background limits they
        // lift) exist from Android 11.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return try {
                startForeground(NOTIFICATION_ID, notification)
                true
            } catch (_: Exception) {
                false
            }
        }
        var type = 0
        if (granted(Manifest.permission.RECORD_AUDIO)) {
            type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        }
        if (video && granted(Manifest.permission.CAMERA)) {
            type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
        }
        if (type == 0) return false
        return try {
            startForeground(NOTIFICATION_ID, notification, type)
            true
        } catch (e: Exception) {
            // Camera refused (e.g. revoked mid-call): keep at least the voice.
            try {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                )
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun granted(permission: String): Boolean =
        checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun buildNotification(title: String, text: String): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Ongoing calls",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shown while a call is in progress"
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }
        val open = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        }
        val pending = PendingIntent.getActivity(
            this,
            0,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher_monochrome)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(pending)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_CALL)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "ongoing_call"
        private const val NOTIFICATION_ID = 4711
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_VIDEO = "video"

        /** The "us/ongoing_call" channel: start {title, text, video} and stop. */
        fun attach(engine: FlutterEngine, context: Context) {
            val app = context.applicationContext
            MethodChannel(engine.dartExecutor.binaryMessenger, "us/ongoing_call")
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "start" -> {
                            val intent = Intent(app, OngoingCallService::class.java).apply {
                                putExtra(EXTRA_TITLE, call.argument<String>("title"))
                                putExtra(EXTRA_TEXT, call.argument<String>("text"))
                                putExtra(EXTRA_VIDEO, call.argument<Boolean>("video") ?: false)
                            }
                            try {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                    app.startForegroundService(intent)
                                } else {
                                    app.startService(intent)
                                }
                                result.success(true)
                            } catch (e: Exception) {
                                // E.g. not allowed to start from the background.
                                result.success(false)
                            }
                        }
                        "stop" -> {
                            app.stopService(Intent(app, OngoingCallService::class.java))
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                }
        }
    }
}
