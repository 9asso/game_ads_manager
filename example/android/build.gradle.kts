allprojects {
    repositories {
        google()
        mavenCentral()
        // Mediation SDKs that are not on Maven Central (game_ads_manager):
        maven { url = uri("https://android-sdk.is.com/") } // ironSource
        maven { url = uri("https://dl-maven-android.mintegral.com/repository/mbridge_android_sdk_oversea") } // Mintegral
        maven { url = uri("https://artifact.bytedance.com/repository/pangle/") } // Pangle
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
