import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: create android/key.properties (never commit it) with
//   storeFile=<path to .jks>  storePassword=...  keyAlias=...  keyPassword=...
// Without it, release builds fall back to the debug key so `flutter run --release` works.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.gtongfa.audifac"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // WMA / APE / WavPack / TTA: our own minimal FFmpeg (tools/ffmpeg/build.sh)
    // behind a small JNI reader.
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    // Unit tests run sink code that logs: android.util.Log returns defaults.
    testOptions {
        unitTests.isReturnDefaultValues = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.gtongfa.audifac"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Same version as the vendored just_audio (packages/just_audio): the DSP
    // sink wraps its DefaultAudioSink.
    implementation("androidx.media3:media3-exoplayer:1.9.4")
    implementation("androidx.media3:media3-extractor:1.9.4") // AIFF / DSD extractors
    // FFmpeg audio decoders (AC-3, E-AC-3, DTS, TrueHD, MP2, ALAC, …) built by
    // Jellyfin against media3 1.9.
    implementation("org.jellyfin.media3:media3-ffmpeg-decoder:1.9.0+1")
    testImplementation("junit:junit:4.13.2")
}
