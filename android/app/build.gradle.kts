import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing details are read from android/key.properties, which is in
// .gitignore and must never be committed: it holds the passwords to the one
// key that can ever publish updates of this app.
//
// When the file is absent — a fresh clone of the repository, or a marker
// checking out the project — the release build falls back to Flutter's debug
// key so that `flutter build apk --release` still produces something that
// runs. Such a build will not upload to Google Play, which is the correct
// outcome: an unsigned-by-you release should fail loudly at the store rather
// than quietly ship under a throwaway key.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.notenest.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17

        // Required by flutter_local_notifications, which uses java.time to
        // work out when a reminder is due. Desugaring rewrites those calls so
        // they also run on Android versions that never shipped java.time.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // The identity of the app on the Play Store and on every device that
        // installs it. It can never be changed after the first upload, and it
        // must match the package_name in android/app/google-services.json or
        // the Google Services plugin fails the build.
        applicationId = "com.notenest.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Desugaring adds a support library to the app, which can push a
        // debug build past the single-dex method limit. On minSdk 21 and above
        // this costs nothing at runtime.
        multiDexEnabled = true
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // Code shrinking is deliberately left off.
            //
            // R8 removes classes it cannot see being used, and several of this
            // app's packages are reached by reflection rather than by a direct
            // call: sqflite's platform channel, the Syncfusion PDF viewer and
            // firebase_auth's provider classes. Turning minification on
            // without a tested set of keep rules produces a release build that
            // crashes where the debug build does not — the worst class of bug
            // to find, because it only exists in the build you ship. The APK
            // is a few megabytes larger this way, and correct.
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

// The desugaring support library itself. This block belongs at the top level,
// outside `android { }`.
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
