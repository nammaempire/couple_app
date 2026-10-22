import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing details live in android/key.properties, which is gitignored
// and never committed. Without it, release builds fall back to the debug key
// so the project still builds on a fresh clone.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.nammaempire.together"
    // Pinned rather than inherited: the Agora plugin's AndroidX dependencies
    // require 34+, and this must not drift below that.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (calendar reminders).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.nammaempire.together"
        // Firebase Auth requires 23+; Agora requires 21+.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8: removes unused Java/Kotlin code and resources. Keep rules
            // for the calling SDK are in proguard-rules.pro.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        jniLibs {
            // Agora ships optional extensions this app never turns on
            // (calls use plain audio/video only). Each is 1-10 MB per CPU type.
            // If one of these features is ever added, remove its line.
            excludes += listOf(
                "**/libagora_clear_vision_extension.so",      // video enhancement
                "**/libagora_lip_sync_extension.so",          // lip sync avatars
                "**/libagora_spatial_audio_extension.so",     // 3D audio
                "**/libagora_ai_noise_suppression_extension.so",
                "**/libagora_ai_noise_suppression_ll_extension.so",
                "**/libagora_ai_echo_cancellation_extension.so",
                "**/libagora_ai_echo_cancellation_ll_extension.so",
                "**/libagora_segmentation_extension.so",      // virtual background
                "**/libagora_face_capture_extension.so",
                "**/libagora_face_detection_extension.so",
                "**/libagora_audio_beauty_extension.so",      // voice effects
                "**/libagora_content_inspect_extension.so",   // moderation
                "**/libagora_video_av1_encoder_extension.so",
                "**/libagora_video_quality_analyzer_extension.so",
                "**/libagora_screen_capture_extension.so",    // screen sharing
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Java 8+ time APIs on older Android, for scheduled reminders.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
