// Javítás a com.android.prefs.AndroidLocationsException hibára, ha az ANDROID_PREFS_ROOT és ANDROID_USER_HOME egyszerre van beállítva
try {
    val processEnv = Class.forName("java.lang.ProcessEnvironment")
    val envField = processEnv.getDeclaredField("theEnvironment")
    envField.isAccessible = true
    @Suppress("UNCHECKED_CAST")
    (envField.get(null) as? MutableMap<String, String>)?.remove("ANDROID_PREFS_ROOT")

    val ciEnvField = processEnv.getDeclaredField("theCaseInsensitiveEnvironment")
    ciEnvField.isAccessible = true
    @Suppress("UNCHECKED_CAST")
    (ciEnvField.get(null) as? MutableMap<String, String>)?.remove("ANDROID_PREFS_ROOT")
} catch (e: Throwable) {
    // Figyelmen kívül hagyható nem Windows rendszeren vagy korlátozott reflexiónál
}

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
