import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. The keystore and `android/key.properties` are NEVER committed (both are gitignored; the
// release workflow writes them from CI secrets). Without them a release build is signed with the debug key and
// is only good for trying the app; set DNDREADER_REQUIRE_RELEASE_SIGNING=1 (the release workflow does) and a
// missing keystore fails the build instead. See docs/android-release.md.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

// versionCode is derived from the version in pubspec.yaml so it only ever goes up as the version does:
//   major*1_000_000 + minor*10_000 + patch*100 + build number      (0.2.2+1 -> 20201)
// Flutter adds 1000 * ABI on top for split APKs (armeabi-v7a 1, arm64-v8a 2, x86_64 4). Needs patch <= 99 and
// build <= 99; the check below fails the build rather than let a code collide.
val versionParts = flutter.versionName.substringBefore("-").split(".").map { it.toIntOrNull() ?: 0 }
val derivedVersionCode =
    versionParts[0] * 1_000_000 + versionParts[1] * 10_000 + versionParts[2] * 100 + flutter.versionCode
require(versionParts.size == 3 && versionParts[1] < 100 && versionParts[2] < 100 && flutter.versionCode < 100) {
    "version ${flutter.versionName}+${flutter.versionCode} does not fit the versionCode scheme (see build.gradle.kts)"
}

android {
    namespace = "io.github.thisisankit27.dndreader"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.thisisankit27.dndreader"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26 // owner decision: docs/progress.md (Android M1)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = derivedVersionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                if (System.getenv("DNDREADER_REQUIRE_RELEASE_SIGNING") == "1") {
                    throw GradleException("android/key.properties is missing: a release build must be signed with the release keystore")
                }
                logger.warn("WARNING: no android/key.properties; signing the release build with the DEBUG key (not distributable)")
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
