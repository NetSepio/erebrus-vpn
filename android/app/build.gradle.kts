import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun hasSigningBlock(prefix: String): Boolean {
    return listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .all { !keystoreProperties.getProperty("$prefix.$it").isNullOrBlank() }
}

val hasPlaystoreSigning = hasSigningBlock("playstore")
val hasDappstoreSigning = hasSigningBlock("dappstore")

val isReleaseBuild = gradle.startParameter.taskNames
    .any { it.contains("Release", ignoreCase = true) }

val requestedFlavor = gradle.startParameter.taskNames
    .firstOrNull { task ->
        task.contains("playstore", ignoreCase = true) ||
            task.contains("dappstore", ignoreCase = true)
    }
    ?.let { task ->
        when {
            task.contains("dappstore", ignoreCase = true) -> "dappstore"
            task.contains("playstore", ignoreCase = true) -> "playstore"
            else -> null
        }
    }

if (isReleaseBuild) {
    when (requestedFlavor) {
        "playstore" -> {
            if (!hasPlaystoreSigning) {
                error(
                    "Play Store release signing is not configured. Fill in the " +
                        "playstore.* values in android/key.properties, then build again."
                )
            }
        }
        "dappstore" -> {
            if (!hasDappstoreSigning) {
                error(
                    "dApp Store release signing is not configured. Fill in the " +
                        "dappstore.* values in android/key.properties, then build again."
                )
            }
        }
        else -> {
            error(
                "Release builds require an explicit flavor. Use --flavor playstore " +
                    "for Google Play or --flavor dappstore for the Solana dApp Store."
            )
        }
    }
}

android {
    namespace = "com.erebrus.vpn"
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.erebrus.vpn"
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // libbox (sing-box mobile core) is built for arm64 only.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
        missingDimensionStrategy("store", "playstore")
    }

    flavorDimensions += "store"
    productFlavors {
        create("playstore") {
            dimension = "store"
        }
        create("dappstore") {
            dimension = "store"
        }
    }

    signingConfigs {
        create("playstoreRelease") {
            enableV2Signing = true
            enableV3Signing = true
            if (hasPlaystoreSigning) {
                keyAlias = keystoreProperties.getProperty("playstore.keyAlias")
                keyPassword = keystoreProperties.getProperty("playstore.keyPassword")
                storeFile = file(keystoreProperties.getProperty("playstore.storeFile"))
                storePassword = keystoreProperties.getProperty("playstore.storePassword")
            }
        }
        create("dappstoreRelease") {
            enableV2Signing = true
            enableV3Signing = true
            if (hasDappstoreSigning) {
                keyAlias = keystoreProperties.getProperty("dappstore.keyAlias")
                keyPassword = keystoreProperties.getProperty("dappstore.keyPassword")
                storeFile = file(keystoreProperties.getProperty("dappstore.storeFile"))
                storePassword = keystoreProperties.getProperty("dappstore.storePassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    androidComponents {
        onVariants { variant ->
            val flavorName = variant.productFlavors
                .firstOrNull { it.first == "store" }
                ?.second

            if (variant.buildType == "release") {
                when (flavorName) {
                    "playstore" -> {
                        variant.signingConfig.setConfig(signingConfigs.getByName("playstoreRelease"))
                    }
                    "dappstore" -> {
                        variant.signingConfig.setConfig(signingConfigs.getByName("dappstoreRelease"))
                    }
                }
            }
        }
    }
}

// Default debug builds to playstore so `flutter run` works without --flavor.
androidComponents {
    beforeVariants { variantBuilder ->
        val flavorName = variantBuilder.productFlavors
            .firstOrNull { it.first == "store" }
            ?.second
        if (variantBuilder.buildType == "debug" && flavorName == "dappstore") {
            variantBuilder.enable = false
        }
    }
}

// Flutter looks for app-debug.apk when --flavor is omitted; flavored builds emit
// app-playstore-debug.apk. Mirror the playstore debug artifact so IDE Run still works.
tasks.configureEach {
    if (name == "assemblePlaystoreDebug") {
        doLast {
            val flutterApkDir = layout.buildDirectory.dir("outputs/flutter-apk").get().asFile
            val src = flutterApkDir.resolve("app-playstore-debug.apk")
            val dst = flutterApkDir.resolve("app-debug.apk")
            if (src.exists()) {
                src.copyTo(dst, overwrite = true)
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // sing-box mobile core — built via scripts/build-libbox.sh into
    // android/app/libs/libbox.aar (provides io.nekohasekai.libbox.*).
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar"))))
    // WireGuard (x25519) keypair generation.
    implementation("org.bouncycastle:bcprov-jdk18on:1.78.1")
    // WebView proxy override for in-app browser over the local sing-box mixed inbound.
    implementation("androidx.webkit:webkit:1.12.1")
    // FlutterView uses WindowInfoTracker; sidecar stubs must be on the APK classpath.
    implementation("androidx.window:window:1.3.0")
}

flutter {
    source = "../.."
}