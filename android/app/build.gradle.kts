import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // Plugin del módulo de Flutter
    id("dev.flutter.flutter-gradle-plugin")
    // Google Services en el módulo app (para Firebase)
    id("com.google.gms.google-services")
}

android {
    namespace = "com.flygo.rd"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.flygo.rd"
        minSdk = 24
        targetSdk = 35

        // ⚠️ Sube versionCode si ya instalaste una versión mayor anteriormente
        versionCode = 2
        versionName = "1.0.1"

        vectorDrawables { useSupportLibrary = true }
        // multiDexEnabled = true // solo si lo necesitas
    }

    // ===== Firma release (lee key.properties) =====
    signingConfigs {
        create("release") {
            val props = Properties()
            val f = rootProject.file("key.properties")
            if (f.exists()) {
                props.load(FileInputStream(f))
                val storeFileProp = props.getProperty("storeFile")
                val storePasswordProp = props.getProperty("storePassword")
                val keyAliasProp = props.getProperty("keyAlias")
                val keyPasswordProp = props.getProperty("keyPassword")

                if (!storeFileProp.isNullOrBlank()
                    && !storePasswordProp.isNullOrBlank()
                    && !keyAliasProp.isNullOrBlank()
                    && !keyPasswordProp.isNullOrBlank()
                    && file(storeFileProp!!).exists()
                ) {
                    storeFile = file(storeFileProp)
                    storePassword = storePasswordProp
                    keyAlias = keyAliasProp
                    keyPassword = keyPasswordProp

                    // 🔐 HABILITA firmas V1/V2 (necesarias en Android 7/8/9)
                    isV1SigningEnabled = true
                    isV2SigningEnabled = true

                    println("✅ Firma release configurada (keystore: $storeFileProp, alias: $keyAliasProp)")
                } else {
                    println("⚠️  Firma release NO configurada: faltan campos o el keystore no existe.")
                }
            } else {
                println("⚠️  key.properties no encontrado. Se construirá release sin firma personalizada.")
            }
        }
    }

    buildTypes {
        getByName("debug") {
            isMinifyEnabled = false
        }
        getByName("release") {
            // Usa la firma solo si está configurada
            signingConfigs.findByName("release")?.let { sc ->
                signingConfig = sc
            }
            // Para facilitar instalación directa mientras probamos:
            isMinifyEnabled = false
            isShrinkResources = false

            // Si luego quieres optimizar para Play Store, activa y añade proguard-rules.pro
            // isMinifyEnabled = true
            // isShrinkResources = true
            // proguardFiles(
            //     getDefaultProguardFile("proguard-android-optimize.txt"),
            //     "proguard-rules.pro"
            // )
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
        resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" }
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
    // implementation("androidx.multidex:multidex:2.0.1") // solo si activas multidex
}
