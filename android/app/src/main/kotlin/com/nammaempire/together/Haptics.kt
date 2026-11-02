package com.nammaempire.together

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * A real vibration (Flutter's HapticFeedback is only a light tick), used
 * when something from the partner arrives while the app is open, e.g. a
 * love note. Channel "us/haptics", method "buzz" with a pattern of
 * millisecond [off, on, off, on, …] timings.
 */
object Haptics {
    fun attach(engine: FlutterEngine, context: Context) {
        val app = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, "us/haptics")
            .setMethodCallHandler { call, result ->
                if (call.method != "buzz") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val pattern = (call.argument<List<Int>>("pattern") ?: listOf(0, 120, 90, 160))
                    .map { it.toLong() }
                    .toLongArray()
                result.success(buzz(app, pattern))
            }
    }

    private fun buzz(context: Context, pattern: LongArray): Boolean {
        val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                ?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        if (vibrator == null || !vibrator.hasVibrator()) return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(pattern, -1)
            }
            true
        } catch (_: Exception) {
            false
        }
    }
}
