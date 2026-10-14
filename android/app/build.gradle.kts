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
// When the file is absent the release build FAILS. It used to fall back to
// Flutter's debug key so that a fresh clone could still build, and the comment
// here claimed that was safe because the store would reject it. That is the
// wrong place to find out. A debug-signed APK installs, runs, and looks
// finished; it is only at upload, or worse on somebody's phone, that it turns
// out to be signed with a key shared by every Flutter project on earth.
//
// A marker or a CI job that genuinely wants an unsigned-by-you build asks for
// it out loud:  -PallowDebugSigning=true
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
            } else if (project.findProperty("allowDebugSigning") == "true") {
                logger.warn(
                    "NoteNest: android/key.properties is missing, so this " +
                    "release build is signed with the DEBUG key because " +
                    "-PallowDebugSigning=true was passed. It cannot be " +
                    "published and must not be given to anyone as a release."
                )
                signingConfigs.getByName("debug")
            } else {
                throw GradleException(
                    "NoteNest release build has no signing key.\n\n" +
                    "android/key.properties was not found, so this build " +
                    "cannot be signed with the upload key.\n" +
                    "  * To build a real release: create android/key.properties " +
                    "from android/key.properties.example.\n" +
                    "  * To build an UNPUBLISHABLE debug-signed release on " +
                    "purpose: add -PallowDebugSigning=true"
                )
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
