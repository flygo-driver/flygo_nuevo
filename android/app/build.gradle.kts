import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.flygo.rd"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.flygo.rd"
        minSdk = 24
        targetSdk = 35
        versionCode = 2
        versionName = "1.0.1"
        vectorDrawables { useSupportLibrary = true }
    }

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
            // usa la firma si está disponible
            signingConfigs.findByName("release")?.let { signingConfig = it }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions { jvmTarget = "17" }

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
    // implementation("androidx.multidex:multidex:2.0.1") // solo si habilitas multidex
}
