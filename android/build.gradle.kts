// android/build.gradle.kts - simple y correcto para Flutter moderno

tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}
