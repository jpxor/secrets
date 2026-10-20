import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.secretskeeper.secrets"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.secretskeeper.secrets"
        manifestPlaceholders["appAuthRedirectScheme"] = "app.secretskeeper.secrets"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            val signingFile = rootProject.file("key.properties")
            if (signingFile.exists()) {
                val props = Properties().apply { signingFile.inputStream().use { load(it) } }
                signingConfig = signingConfigs.create("distribution") {
                    storeFile = file(props.getProperty("storeFile"))
                    storePassword = props.getProperty("storePassword")
                    keyAlias = props.getProperty("keyAlias")
                    keyPassword = props.getProperty("keyPassword")
                }
            }
        }
    }
    packaging {
        resources.excludes += setOf("META-INF/DEPENDENCIES", "META-INF/NOTICE.md", "META-INF/LICENSE.md", "OSGI-INF/**")
    }
}

dependencies {
    implementation("androidx.biometric:biometric:1.1.0")
    implementation("androidx.work:work-runtime-ktx:2.10.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("net.openid:appauth:0.11.1")
    implementation("com.google.android.gms:play-services-auth:22.0.0")
    implementation("org.eclipse.jgit:org.eclipse.jgit:6.10.1.202505221210-r")
    implementation("org.eclipse.jgit:org.eclipse.jgit.ssh.jsch:6.10.1.202505221210-r") {
        exclude(group = "com.jcraft", module = "jsch")
    }
    implementation("com.github.mwiede:jsch:0.2.26")
    implementation("org.slf4j:slf4j-nop:1.7.36")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    testImplementation("org.apache.sshd:sshd-sftp:2.14.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
