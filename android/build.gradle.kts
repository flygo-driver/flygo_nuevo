// android/build.gradle.kts - simple y correcto para Flutter moderno

import java.io.File

// Gradle/Android en OneDrive suele fallar con AccessDeniedException en .so nativos.
// Salida de build fuera de OneDrive (no afecta firma ni código de la app).
val flygoAndroidBuildRoot = File(
    System.getenv("LOCALAPPDATA") ?: System.getProperty("user.home"),
    "flygo-nuevo-android-build",
)
rootProject.layout.buildDirectory.set(flygoAndroidBuildRoot)
subprojects {
    layout.buildDirectory.set(File(flygoAndroidBuildRoot, name))
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
