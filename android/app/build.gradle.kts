// android/app/build.gradle.kts - FLYGO_NUEVO (DEV)

import java.io.File
import java.util.Properties
import java.io.FileInputStream

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

    compileSdk = flutter.compileSdkVersion

    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.flygo.rd2"

        // ⚠️ SUBIMOS EL MIN SDK A 24 (por url_launcher_android)
        minSdk = 24

        // TARGET SDK LO TOMAMOS DE FLUTTER
        targetSdk = flutter.targetSdkVersion

        versionCode = 3
        versionName = "1.0.2"

        vectorDrawables {
            useSupportLibrary = true
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
                "proguard-android-optimize.txt",
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
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

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.2")
}

// Flutter CLI espera el APK en <raíz_proyecto>/build/app/outputs/flutter-apk/, pero AGP lo genera
// en android/app/build/outputs/flutter-apk/. Sin esta copia, `flutter run` falla aunque Gradle sea OK.
afterEvaluate {
    listOf("assembleDebug", "assembleRelease").forEach { taskName ->
        tasks.named(taskName).configure {
            doLast {
                val flutterRoot = rootProject.projectDir.parentFile
                val destDir = File(flutterRoot, "build/app/outputs/flutter-apk")
                destDir.mkdirs()
                val srcDir = layout.buildDirectory.get().asFile.resolve("outputs/flutter-apk")
                if (!srcDir.isDirectory) return@doLast
                srcDir.listFiles().orEmpty()
                    .filter { it.isFile && it.name.endsWith(".apk") }
                    .forEach { apk -> apk.copyTo(File(destDir, apk.name), overwrite = true) }
            }
        }
    }
}
