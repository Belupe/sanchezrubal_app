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
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    // Firebase: procesa app/google-services.json y genera los recursos que lee
    // firebase_core al arrancar. Sin este plugin el JSON se ignora y la app
    // nunca obtiene token de FCM — y no da ningún error: simplemente no llegan
    // las notificaciones. Se declara aquí sin aplicar; se aplica en
    // app/build.gradle.kts.
    id("com.google.gms.google-services") version "4.5.0" apply false
}

include(":app")
