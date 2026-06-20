allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Algunos plugins transitivos (p. ej. passkeys_doctor, que llega vía
// supabase_flutter) fijan compileSdk=35 en su propio bloque android{}, pero
// device_info_plus y package_info_plus exigen 36 y el AAR metadata check
// falla. Sobreescribimos compileSdk a 36 en todos los módulos Android, en
// afterEvaluate (después de que el plugin fije el suyo). Reflexión para no
// acoplarnos a una API concreta de AGP 9.
fun forceCompileSdk36(project: org.gradle.api.Project) {
    val androidExt = project.extensions.findByName("android") ?: return
    runCatching {
        val current = (androidExt.javaClass.methods
            .firstOrNull { it.name == "getCompileSdk" && it.parameterCount == 0 }
            ?.invoke(androidExt) as? Int) ?: 0
        if (current in 1 until 36) {
            androidExt.javaClass.methods
                .firstOrNull { it.name == "setCompileSdk" && it.parameterCount == 1 }
                ?.invoke(androidExt, 36)
        }
    }
}

// Registrado ANTES de evaluationDependsOn(":app") para que el afterEvaluate
// quede enganchado antes de que :app fuerce la evaluación de los plugins.
subprojects {
    if (state.executed) forceCompileSdk36(this) else afterEvaluate { forceCompileSdk36(this) }
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
