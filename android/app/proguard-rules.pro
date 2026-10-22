# Release shrinking (R8) keep rules.

# Agora calls: the native SDK reaches its Java classes through JNI.
-keep class io.agora.** { *; }
-dontwarn io.agora.**

# Flutter's deferred components reference Play Core, which isn't used.
-dontwarn com.google.android.play.core.**
