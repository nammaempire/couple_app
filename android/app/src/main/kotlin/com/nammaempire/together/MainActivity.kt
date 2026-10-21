package com.nammaempire.together

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * A [FlutterFragmentActivity] rather than a plain FlutterActivity because
 * local_auth (the app lock) shows the system biometric prompt as a fragment.
 */
class MainActivity : FlutterFragmentActivity() {
    private val screenPrivacy = ScreenPrivacy(this)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        screenPrivacy.attach(flutterEngine)
        DeviceInfo.attach(flutterEngine)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        screenPrivacy.detach()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
