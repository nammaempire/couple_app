allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Some plugins (agora_rtc_engine among them) still declare an old compileSdk in
// their own build.gradle, while the AndroidX libraries they pull in require 34+.
// That mismatch fails `checkDebugAarMetadata`. Raising compileSdk only changes
// which APIs are visible at compile time — it does not touch minSdk or
// targetSdk, so no devices are dropped and no runtime behaviour changes.
//
// The setter is found reflectively because its name differs across Android
// Gradle Plugin versions; a direct reference would break on an AGP upgrade.
fun Project.enforceCompileSdk(target: Int) {
    val androidExtension = extensions.findByName("android") ?: return
    val methods = androidExtension.javaClass.methods

    val setter = methods.firstOrNull { method ->
        method.name == "setCompileSdk" && method.parameterTypes.size == 1
    } ?: methods.firstOrNull { method ->
        method.name == "setCompileSdkVersion" &&
            method.parameterTypes.size == 1 &&
            method.parameterTypes[0] == Int::class.javaPrimitiveType
    }

    runCatching { setter?.invoke(androidExtension, target) }
}

// Registered before the evaluationDependsOn block below, which would otherwise
// force :app to evaluate first and make afterEvaluate illegal on it. The state
// check covers any subproject that has already been evaluated regardless.
subprojects {
    if (state.executed) {
        enforceCompileSdk(36)
    } else {
        afterEvaluate { enforceCompileSdk(36) }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
