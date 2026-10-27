plugins {
    id("com.android.library")
}

val godotLibVersion: String by project
val applovinSdkVersion: String by project
val pluginVersion: String by project

// Output: applovin_max-debug.aar / applovin_max-release.aar
base {
    archivesName.set("applovin_max")
}

android {
    namespace = "com.vicenterusso.godot.applovinmax"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
        buildConfigField("String", "PLUGIN_VERSION", "\"$pluginVersion\"")
    }

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    // Both are provided at export time: Godot by the export template and the
    // AppLovin SDK by the editor export plugin (see addons/applovin_max/export_plugin.gd).
    compileOnly("org.godotengine:godot:$godotLibVersion")
    compileOnly("com.applovin:applovin-sdk:$applovinSdkVersion")
}

// Copies the built AARs into the Godot addon folder.
val copyAarsToAddon by tasks.registering(Copy::class) {
    dependsOn("assembleDebug", "assembleRelease")
    from(layout.buildDirectory.dir("outputs/aar"))
    include("applovin_max-debug.aar", "applovin_max-release.aar")
    into(rootProject.layout.projectDirectory.dir("../addons/applovin_max/bin/android"))
}

tasks.named("assemble") {
    finalizedBy(copyAarsToAddon)
}
