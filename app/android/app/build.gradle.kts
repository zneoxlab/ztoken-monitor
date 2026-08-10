import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeyPropertiesFile = rootProject.file("key.properties")
val releaseKeyProperties = Properties()
if (releaseKeyPropertiesFile.exists()) {
    releaseKeyPropertiesFile.inputStream().use(releaseKeyProperties::load)
}

fun requiredReleaseProperty(name: String): String =
    releaseKeyProperties.getProperty(name)?.trim().orEmpty().also {
        check(it.isNotEmpty()) { "android/key.properties 缺少 $name" }
    }

val releasePassword: String? = if (releaseKeyPropertiesFile.exists()) {
    val passwordFile = rootProject.file(requiredReleaseProperty("passwordFile"))
    check(passwordFile.isFile) { "Android Release 签名口令文件不存在: $passwordFile" }
    passwordFile.readText().trim().also {
        check(it.isNotEmpty()) { "Android Release 签名口令文件为空" }
    }
} else {
    null
}

android {
    namespace = "com.zneox.ztoken.ztoken_monitor"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.zneox.ztoken.ztoken_monitor"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "distribution"
    productFlavors {
        create("website") {
            dimension = "distribution"
        }
        create("store") {
            dimension = "distribution"
        }
    }

    signingConfigs {
        if (releaseKeyPropertiesFile.exists()) {
            create("release") {
                keyAlias = requiredReleaseProperty("keyAlias")
                keyPassword = releasePassword
                storeFile = rootProject.file(requiredReleaseProperty("storeFile"))
                storePassword = releasePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseKeyPropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                null
            }
        }
    }
}

tasks.matching {
    it.name.startsWith("package") && it.name.endsWith("Release")
}.configureEach {
    doFirst {
        check(releaseKeyPropertiesFile.exists()) {
            "Release 构建需要 android/key.properties，请参考 key.properties.example"
        }
    }
}

flutter {
    source = "../.."
}
