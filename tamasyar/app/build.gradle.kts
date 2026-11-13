plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "ir.honarmardomi.tamasyar"
    compileSdk = 35
    defaultConfig {
        applicationId = "ir.honarmardomi.tamasyar"
        minSdk = 24
        targetSdk = 35
        versionCode = 3
        versionName = "0.3.0"
    }
    signingConfigs {
        val keyPath = System.getenv("TAMASYAR_KEYSTORE_PATH")
        if (!keyPath.isNullOrBlank()) {
            create("production") {
                storeFile = file(keyPath)
                storePassword = System.getenv("TAMASYAR_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("TAMASYAR_KEY_ALIAS")
                keyPassword = System.getenv("TAMASYAR_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            if (signingConfigs.findByName("production") != null)
                signingConfig = signingConfigs.getByName("production")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    implementation("androidx.core:core:1.15.0")
    implementation("androidx.work:work-runtime:2.12.0")
}

