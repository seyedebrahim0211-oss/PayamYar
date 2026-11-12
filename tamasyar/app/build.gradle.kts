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
        versionCode = 1
        versionName = "0.1.0"
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
