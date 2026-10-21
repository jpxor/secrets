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
            val signingFile = rootProject.file("key.properties")
            val environmentStore = System.getenv("SECRETS_KEYSTORE")
            if (!environmentStore.isNullOrBlank()) {
                signingConfig = signingConfigs.create("distribution") {
                    storeFile = file(environmentStore)
                    storePassword = System.getenv("SECRETS_STORE_PASSWORD")
                    keyAlias = System.getenv("SECRETS_KEY_ALIAS") ?: "secrets"
                    keyPassword = System.getenv("SECRETS_KEY_PASSWORD") ?: storePassword
                }
            } else if (signingFile.exists()) {
                val props = Properties().apply { signingFile.inputStream().use { load(it) } }
                signingConfig = signingConfigs.create("distribution") {
                    storeFile = file(props.getProperty("storeFile"))
                    storePassword = props.getProperty("storePassword")
                    keyAlias = props.getProperty("keyAlias")
                    keyPassword = props.getProperty("keyPassword")
                }
            } else if (gradle.startParameter.taskNames.any { it.endsWith("assembleRelease") || it.endsWith("bundleRelease") }) {
                throw GradleException("Release signing is required. Use scripts/build-release.ps1 or supply android/key.properties; debug signing is never used for releases.")
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
    implementation("com.google.android.gms:play-services-auth:22.0.0")
    implementation("com.github.mwiede:jsch:0.2.26")
    // Supplies modern SFTP algorithms on Android versions without Java 15 crypto providers.
    implementation("org.bouncycastle:bcprov-jdk18on:1.86")
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

// Lint scans this generated file but AGP does not otherwise track its contents.
// Include it so correcting Flutter's Windows escaping invalidates stale lint results.
tasks.matching { it.name.startsWith("lintAnalyze") }.configureEach {
    inputs.file(rootProject.file("local.properties")).withPropertyName("localSdkProperties").optional()
}
