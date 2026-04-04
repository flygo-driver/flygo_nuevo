// android/build.gradle.kts - solo clean

tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}
