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
// and never committed (see README, "Release signing"). A release build without
// it stops with an error, so a debug-signed build can never reach Google Play.
// To try a release build on your own phone before the key exists, set the
// environment variable US_ALLOW_DEBUG_SIGNING=true (debug-signed, test only).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val allowDebugSigning = System.getenv("US_ALLOW_DEBUG_SIGNING") == "true"

gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any { task ->
        task.project == project &&
            (task.name.startsWith("assemble") || task.name.startsWith("bundle")) &&
            task.name.contains("Release")
    }
    if (buildsRelease && !hasReleaseKeystore && !allowDebugSigning) {
        throw GradleException(
            "Release builds need the upload key: create android/key.properties " +
                "(see README, \"Release signing\"). For a test build on your " +
                "own phone only, set US_ALLOW_DEBUG_SIGNING=true.",
        )
    }
}

android {
    namespace = "com.nammaempire.together"
    // Pinned rather than inherited: AndroidX dependencies require 34+, and
    // this must not drift below that.
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
        // Firebase Auth requires 23+; WebRTC requires 21+.
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
