plugins {
    id("com.android.application")
    // A Flutter Gradle beépülő modult az Android és Kotlin modulok után kell alkalmazni.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.freelib.free_lib_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Egyedi alkalmazás-azonosító (Application ID)
        applicationId = "com.freelib.free_lib_app"
        // SDK verziók a Flutter konfiguráció alapján
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // A pubspec.yaml-ben megadott verziókód és verziónév használata
        versionCode = flutter.versionCode
        versionName = "${flutter.versionName} (by @Lithexf | Dart/Flutter | 5643 lines)"
    }

    buildTypes {
        release {
            // Aláírás debug kulccsal, hogy a kiadási (release) APK közvetlenül telepíthető legyen
            // és az APK fájl metaadatai/ikonja érvényes aláírással jelenjenek meg.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
    // Az ML Kit vonalkód-modell közvetlen beépítése az APK-ba az azonnali, offline működéshez
    implementation("com.google.mlkit:barcode-scanning:17.3.0")
}
