plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("keystore.properties")
val keystoreProperties = java.util.Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(java.io.FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.paisatrack"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.paisatrack"
        // PLAN.md §2 requires Android 8.0 (API 26) as the minimum. Pinned
        // explicitly instead of flutter.minSdkVersion so the SMS/Keystore floor
        // does not drift with the Flutter toolchain default.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties.getProperty("storeFile") ?: System.getenv("KEYSTORE_STORE_FILE")
            if (storeFilePath != null) {
                storeFile = file(storeFilePath)
                storePassword = keystoreProperties.getProperty("storePassword") ?: System.getenv("KEYSTORE_STORE_PASSWORD")
                keyAlias = keystoreProperties.getProperty("keyAlias") ?: System.getenv("KEYSTORE_KEY_ALIAS")
                keyPassword = keystoreProperties.getProperty("keyPassword") ?: System.getenv("KEYSTORE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            val hasReleaseStore = keystoreProperties.getProperty("storeFile") != null || System.getenv("KEYSTORE_STORE_FILE") != null
            val isReleaseBuildRequested = gradle.startParameter.taskNames.any {
                it.contains("Release", ignoreCase = true) || it.contains("bundle", ignoreCase = true)
            }

            if (hasReleaseStore) {
                signingConfig = signingConfigs.getByName("release")
            } else if (isReleaseBuildRequested) {
                throw GradleException(
                    "Production release signing is not configured. " +
                    "Please set up keystore.properties (see android/keystore.properties.example) " +
                    "or supply KEYSTORE_* environment variables. See docs/release-signing.md for details."
                )
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }

            isMinifyEnabled = true
            isShrinkResources = true

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // T-050 (ADR 0007): MediaPipe Text Embedder runtime — pin exactly;
    // bumping requires re-running the determinism test and an ADR update.
    implementation("com.google.mediapipe:tasks-text:0.10.26")
    // ADR 0009: pinned on-device LLM runtime.
    implementation("com.google.ai.edge.litertlm:litertlm-android:0.14.0")
    debugImplementation("androidx.test.espresso:espresso-core:3.7.0")
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
