// android/app/build.gradle.kts — RAI Driver (release: key.properties + R8/ProGuard)

import java.io.File
import java.io.FileInputStream
import java.util.Properties

import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Cargar key.properties desde android/key.properties (rootProject = carpeta android)
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.flygo.rd2"

    // androidx.core 1.18.x exige compileSdk 36 + AGP ≥8.9.1 (ver settings.gradle.kts).
    compileSdk = 36

    // jni (transitivo vía plugins) exige NDK 28.2.x; compatible hacia atrás con el resto.
    ndkVersion = "28.2.13676358"

    defaultConfig {
        // applicationId por flavor (cliente = listing actual com.flygo.rd2; conductor = com.flygo.rd2.conductor)
        minSdk = 24

        // Play (ago 2026): API objetivo 36 (Android 16). No depender de flutter.targetSdkVersion (35).
        targetSdk = 36

        // Una sola fuente: pubspec.yaml → version: "nombre+código" (p. ej. 1.0.4+5)
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        vectorDrawables {
            useSupportLibrary = true
        }
    }

    flavorDimensions += "tipo"
    productFlavors {
        create("cliente") {
            dimension = "tipo"
            applicationId = "com.flygo.rd2"
            resValue("string", "app_name", "RAI Driver")
        }
        create("conductor") {
            dimension = "tipo"
            applicationId = "com.flygo.rd2.conductor"
            resValue("string", "app_name", "RAI Conductor")
        }
    }

    val hasReleaseKeystore =
        keystorePropertiesFile.exists() && keystoreProperties.isNotEmpty()

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                val storeFilePath = keystoreProperties["storeFile"] as String
                storeFile = rootProject.file(storeFilePath)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        getByName("debug") {
            isMinifyEnabled = false
        }
        getByName("release") {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }
}

tasks.withType<KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.2")
    // Alineado con image_picker / Photo Picker (recomendación Google Play).
    implementation("androidx.activity:activity:1.9.3")
    implementation("com.android.installreferrer:installreferrer:2.2")
}

// Copia APK y AAB al árbol build/ que espera la CLI de Flutter (por variante de flavor).
// Importante: el plugin de Flutter puede dejar el APK solo en
// `outputs/apk/<flavor>/debug|release/`. Si solo mirábamos `outputs/flutter-apk` y
// hacíamos return, quedaba un APK viejo/corrupto en el destino y `aapt` fallaba
// con "Invalid file" / "Error opening archive".
afterEvaluate {
    fun flavorCap(f: String) = f.replaceFirstChar { it.uppercase() }
    val flavors = listOf("cliente", "conductor")
    flavors.forEach { flavor ->
        val cap = flavorCap(flavor)
        listOf("Debug", "Release").forEach { buildType ->
            tasks.named("assemble${cap}$buildType").configure {
                doLast {
                    val flutterRoot = rootProject.projectDir.parentFile
                    val destDir = File(flutterRoot, "build/app/outputs/flutter-apk")
                    destDir.mkdirs()
                    val buildDir = layout.buildDirectory.get().asFile
                    val lowerBuild = buildType.lowercase()

                    // Solo el APK de ESTE flavor (evita mezclar con app-release.apk genérico
                    // u otros flavors en outputs/flutter-apk).
                    val agpApkDir =
                        buildDir.resolve("outputs/apk/$flavor/$lowerBuild")
                    val fromFlavor = agpApkDir.listFiles().orEmpty()
                        .filter { it.isFile && it.name.endsWith(".apk") }

                    val apksToCopy = if (fromFlavor.isNotEmpty()) {
                        fromFlavor
                    } else {
                        val flutterApkDir = buildDir.resolve("outputs/flutter-apk")
                        flutterApkDir.listFiles().orEmpty()
                            .filter { it.isFile && it.name.endsWith(".apk") }
                    }

                    check(apksToCopy.isNotEmpty()) {
                        "RAI: no se encontró APK para flavor=$flavor buildType=$buildType " +
                            "(esperado en ${agpApkDir.path})"
                    }
                    apksToCopy.forEach { apk ->
                        apk.copyTo(File(destDir, apk.name), overwrite = true)
                    }

                    // Flutter CLI busca `app-<flavor>-release.apk` (universal) o
                    // `app-<abi>-<flavor>-release.apk` (split). AGP emite
                    // `app-<flavor>-<abi>-release.apk` → alias compatibles.
                    val releaseApks = apksToCopy.filter { it.name.endsWith("-release.apk") }
                    val preferredArm64 = releaseApks.firstOrNull {
                        it.name.contains("arm64-v8a", ignoreCase = true)
                    }
                    val primaryRelease = preferredArm64
                        ?: releaseApks.maxByOrNull { it.length() }
                        ?: releaseApks.firstOrNull()

                    if (primaryRelease != null && lowerBuild == "release") {
                        val flavorRelease = File(destDir, "app-$flavor-release.apk")
                        primaryRelease.copyTo(flavorRelease, overwrite = true)
                        if (flavor == "cliente") {
                            primaryRelease.copyTo(
                                File(destDir, "app-release.apk"),
                                overwrite = true,
                            )
                        }
                    }

                    if (lowerBuild == "release") {
                        val abiFlavorRegex =
                            Regex("""app-$flavor-(.+)-release\.apk""")
                        releaseApks.forEach { apk ->
                            val abi = abiFlavorRegex.matchEntire(apk.name)
                                ?.groupValues?.getOrNull(1)
                                ?: return@forEach
                            apk.copyTo(
                                File(destDir, "app-$abi-$flavor-release.apk"),
                                overwrite = true,
                            )
                        }
                    }

                    if (flavor == "cliente" && lowerBuild == "debug") {
                        val debugApk = apksToCopy.firstOrNull {
                            it.name.endsWith("-debug.apk")
                        }
                        if (debugApk != null) {
                            debugApk.copyTo(
                                File(destDir, "app-debug.apk"),
                                overwrite = true,
                            )
                        }
                    }
                }
            }
        }
        listOf("Debug", "Release").forEach { buildType ->
            val variantDir = "${flavor}${buildType}"
            tasks.named("bundle${cap}$buildType").configure {
                doLast {
                    val flutterRoot = rootProject.projectDir.parentFile
                    val srcDir = layout.buildDirectory.get().asFile.resolve("outputs/bundle/$variantDir")
                    if (!srcDir.isDirectory) return@doLast
                    val destDir = File(flutterRoot, "build/app/outputs/bundle/$variantDir")
                    destDir.mkdirs()
                    srcDir.listFiles().orEmpty()
                        .filter { it.isFile && it.name.endsWith(".aab") }
                        .forEach { aab -> aab.copyTo(File(destDir, aab.name), overwrite = true) }
                }
            }
        }
    }

    // Sin esto, `flutter run` llama assembleDebug y no existe (solo cliente/conductor).
    if (tasks.findByName("assembleDebug") == null) {
        tasks.register("assembleDebug") {
            dependsOn("assembleClienteDebug")
        }
    }
    if (tasks.findByName("assembleRelease") == null) {
        tasks.register("assembleRelease") {
            dependsOn("assembleClienteRelease")
        }
    }
}
 