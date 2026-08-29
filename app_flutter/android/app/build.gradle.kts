import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase (push con FCM). Va DESPUÉS del plugin de Android, que es de quien
    // depende. Lee app/google-services.json —que está en .gitignore, nunca se
    // sube— y genera los recursos que firebase_core consulta en el arranque.
    // La versión se declara en android/settings.gradle.kts.
    id("com.google.gms.google-services")
}

// Carga la configuración de firma release desde android/key.properties
// (gitignored, fuera del control de versiones). Si el archivo no existe,
// no se carga nada aquí: los builds de debug siguen funcionando, pero
// cualquier tarea de RELEASE fallará explícitamente (ver taskGraph.whenReady
// más abajo) en vez de firmar con la clave debug (que sería falsificable). [B-09]
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "net.sanchezrubal.portal_familia"
    // 37, no flutter.compileSdkVersion (36): flutter_secure_storage exige que
    // quien depende de él compile contra la API 37 o superior.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "net.sanchezrubal.portal_familia"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Firma SIEMPRE con la clave release. Nunca cae a debug:
            // un AAB/APK de release firmado con la clave debug sería
            // reproducible y falsificable. Si falta el keystore, el build
            // de release falla en tiempo de ejecución (ver más abajo). [B-09]
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// [B-09] Falla el build de RELEASE (nunca el de debug) si falta el keystore, en
// vez de firmar con la clave debug. El chequeo se difiere a tiempo de ejecución:
// si se pusiera dentro de buildTypes.release {} se evaluaría en la fase de
// configuración para CUALQUIER invocación de Gradle (incluido `flutter run` en
// debug) y rompería también el build de debug.
// IMPORTANTE: se engancha a las tareas de release y el chequeo va en doFirst, o
// sea en tiempo de EJECUCIÓN. No usar gradle.taskGraph.whenReady: en el DSL de
// Kotlin de Gradle 9 esa llamada ya no resuelve el Action<TaskExecutionGraph> y
// rompe la compilación del propio build script.
tasks.matching { task ->
    val n = task.name
    n.contains("Release") &&
        (n.startsWith("assemble") || n.startsWith("bundle") || n.startsWith("package"))
}.configureEach {
    doFirst {
        if (!keystorePropertiesFile.exists()) {
            throw GradleException(
                "Falta android/key.properties: no se puede firmar el build de RELEASE.\n" +
                "Crea android/key.properties (gitignored) con keyAlias, keyPassword, " +
                "storeFile y storePassword apuntando al keystore de release.\n" +
                "El build de release NO cae a la firma debug por seguridad."
            )
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
