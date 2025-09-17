plugins {
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.android") apply false
    // Cargador del plugin de Flutter (raíz)
    id("dev.flutter.flutter-plugin-loader") apply false
    // Google Services (versión aquí, sin aplicar en raíz)
    id("com.google.gms.google-services") version "4.4.2" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// (Opcional) reubicar carpeta build global. Si no lo necesitas, puedes borrar este bloque.
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
