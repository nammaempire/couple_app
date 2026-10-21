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
            isMinifyEnabled = false
            isShrinkResources = false
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
    // AppCompat themes (styles.xml) for the app lock's biometric prompt.
    // local_auth only brings it in as a runtime dependency of
    // androidx.biometric, so it is declared here for the theme resources.
    implementation("androidx.appcompat:appcompat:1.8.0")
}
