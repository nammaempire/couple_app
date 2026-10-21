package com.nammaempire.together

import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The `couple_app/device_info` channel used by the private vault (see
 * lib/features/vault/data/device_name.dart).
 *
 * - `deviceName`: the phone's model, e.g. "Pixel 8" or "Samsung SM-S911B",
 *   shown when one partner approves the other's phone. Needs no permission.
 */
object DeviceInfo {
    private const val CHANNEL = "couple_app/device_info"

    fun attach(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "deviceName" -> result.success(deviceName())
                    else -> result.notImplemented()
                }
            }
    }

    private fun deviceName(): String {
        val model = Build.MODEL?.trim().orEmpty()
        val maker = Build.MANUFACTURER?.trim().orEmpty()
        if (model.isEmpty()) return maker.ifEmpty { "Android phone" }
        // Pixels already say "Pixel"; others read better with the maker.
        if (maker.isEmpty() || maker.equals("google", ignoreCase = true) ||
            model.startsWith(maker, ignoreCase = true)
        ) {
            return model
        }
        return maker.replaceFirstChar { it.uppercase() } + " " + model
    }
}
