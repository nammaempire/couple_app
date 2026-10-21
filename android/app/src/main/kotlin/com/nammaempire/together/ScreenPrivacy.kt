package com.nammaempire.together

import android.app.Activity
import android.os.Build
import android.view.WindowManager
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The `couple_app/screen_privacy` channel used by the chat (see
 * lib/core/services/screen_privacy.dart).
 *
 * - `startDetection` / `stopDetection`: screenshot alerts through
 *   [Activity.registerScreenCaptureCallback], Android 14 (API 34) and newer.
 *   It needs only the install-time DETECT_SCREEN_CAPTURE permission, not
 *   access to the user's photos. On older versions it does nothing and
 *   returns false. Each screenshot calls `onScreenshot` back on the channel.
 * - `setSecure`: adds or clears FLAG_SECURE on the window, on every version.
 *   While set, screenshots and recordings come out black and the
 *   recent-apps preview is hidden.
 */
class ScreenPrivacy(private val activity: Activity) {
    private var channel: MethodChannel? = null
    private var captureCallback: Any? = null

    fun attach(engine: FlutterEngine) {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startDetection" -> result.success(startDetection())
                "stopDetection" -> {
                    stopDetection()
                    result.success(null)
                }
                "setSecure" -> {
                    setSecure(call.argument<Boolean>("secure") == true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        this.channel = channel
    }

    fun detach() {
        stopDetection()
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun setSecure(secure: Boolean) {
        val flag = WindowManager.LayoutParams.FLAG_SECURE
        if (secure) activity.window.addFlags(flag) else activity.window.clearFlags(flag)
    }

    private fun startDetection(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return false
        if (captureCallback == null) register()
        return true
    }

    private fun stopDetection() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        if (captureCallback != null) unregister()
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun register() {
        val callback = Activity.ScreenCaptureCallback {
            channel?.invokeMethod("onScreenshot", null)
        }
        activity.registerScreenCaptureCallback(activity.mainExecutor, callback)
        captureCallback = callback
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun unregister() {
        val callback = captureCallback as? Activity.ScreenCaptureCallback ?: return
        activity.unregisterScreenCaptureCallback(callback)
        captureCallback = null
    }

    companion object {
        const val CHANNEL = "couple_app/screen_privacy"
    }
}
