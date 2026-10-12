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
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false

    // Reads android/app/google-services.json and turns it into the Android
    // resources Firebase looks for at startup.
    //
    // `flutterfire configure` writes 4.3.15 here, which is a hardcoded default
    // from January 2023. Paired with Android Gradle Plugin 9.1.0 that is a gap
    // of three and a half years, and an old Gradle plugin against a new AGP is
    // the usual cause of "plugin is not compatible" build failures. 4.5.0 is
    // the current release.
    id("com.google.gms.google-services") version("4.5.0") apply false
}

include(":app")
