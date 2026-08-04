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
    afterEvaluate {
      if (name == "reactive_ble_mobile") {
        extensions.configure<com.android.build.gradle.LibraryExtension> {
            // flutter_reactive_ble 5.5.0 declares 33, while its resolved
            // AndroidX dependencies require 34+. Keep the plugin pinned and
            // compile every Android library against our installed SDK 36.
            compileSdk = 36
        }
      }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
