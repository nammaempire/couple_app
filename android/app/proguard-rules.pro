# Release shrinking (R8) keep rules.

# WebRTC calls (flutter_webrtc): the native library reaches these Java
# classes through JNI, so R8 must keep them.
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**
-keep class com.cloudwebrtc.webrtc.** { *; }

# Flutter's deferred components reference Play Core, which isn't used.
-dontwarn com.google.android.play.core.**
