plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseStorePath = System.getenv("GROWUP_RELEASE_STORE_FILE").orEmpty()
val releaseStorePassword = System.getenv("GROWUP_RELEASE_STORE_PASSWORD").orEmpty()
val releaseKeyAlias = System.getenv("GROWUP_RELEASE_KEY_ALIAS").orEmpty()
val releaseKeyPassword = System.getenv("GROWUP_RELEASE_KEY_PASSWORD").orEmpty()
val hasProductionSigning = listOf(
    releaseStorePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { it.isNotBlank() }
val releaseApplicationId = providers.gradleProperty("GROWUP_APPLICATION_ID")
    .orElse("com.example.growup").get()
val requireProductionSigning = providers.gradleProperty("GROWUP_REQUIRE_PRODUCTION_SIGNING")
    .orElse("false").get().toBoolean()

if (requireProductionSigning) {
    require(releaseApplicationId != "com.example.growup") {
        "Set GROWUP_APPLICATION_ID to the permanent package name before publishing."
    }
    require(hasProductionSigning) {
        "Set all four GROWUP_RELEASE_* signing environment variables before publishing."
    }
    require(!releaseStorePath.endsWith("debug.keystore", ignoreCase = true)) {
        "Use a separate upload keystore instead of Android Debug."
    }
}

android {
    namespace = "com.example.growup"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = releaseApplicationId
        manifestPlaceholders["loginRedirectScheme"] = releaseApplicationId
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (hasProductionSigning) {
        signingConfigs.create("production") {
            storeFile = file(releaseStorePath)
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (hasProductionSigning) "production" else "debug"
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
