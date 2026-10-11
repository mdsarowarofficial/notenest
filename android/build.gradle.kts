allprojects {
    repositories {
        google()
        mavenCentral()

        // Flutter's own engine artifacts (io.flutter:arm64_v8a_debug and the
        // rest) are published here, not to Maven Central. The Flutter Gradle
        // plugin usually adds this itself; naming it explicitly means a build
        // never falls back to searching Maven Central for something that was
        // never there.
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
