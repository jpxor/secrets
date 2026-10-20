# Development process

## Environment

Use Flutter stable, a compatible JDK and Android command-line SDK. Android Studio is not required. Tool downloads go in ignored `.tools/`; no global PATH changes are necessary. Use a real Android device with USB debugging for biometric, screen-lock and background-execution verification. Apple builds require a contributor with macOS/Xcode.

On Windows, use PowerShell 7:

```powershell
./scripts/bootstrap.ps1 -AcceptAndroidLicenses
. ./scripts/env.ps1
./scripts/check.ps1
flutter run -d <device-id>
```

The bootstrap pins Flutter 3.47.7, JDK 17, Android API/build tools 36 and verifies downloaded archive checksums. Omit `-AcceptAndroidLicenses` to handle SDK license prompts yourself. `.tools/` holds SDKs and build caches, not project source. On Linux install the corresponding Flutter 3.47.7, JDK 17 and Android command-line SDK, set JAVA_HOME/ANDROID_HOME, then use `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build apk --debug` and `bash android/gradlew -p android :app:testDebugUnitTest`.

The generated Flutter toolchain currently requires `android.newDsl=false`; built-in Kotlin is enabled. Do not enable the new AGP DSL until the Flutter Gradle plugin supports it. Deprecation warnings for this compatibility flag are expected with AGP 9.1. SDK/IDE upgrades are separate changes requiring build verification.

The check script normalizes Flutter-generated Windows SDK property escaping before Android lint. Gradle tracks that generated file as a lint input so a corrected path does not reuse stale lint results. CI runs Flutter/Android checks on Linux and the Windows-only signing/property regression checks on Windows. Provider account tests and physical device checks remain separate from CI.

## Workflow

1. Read specification/security/progress documents and inspect `git status`.
2. Implement one logical feature, keep platform APIs behind interfaces.
3. Add tests for important boundaries (authenticated encryption, recovery, backup ordering/failures) and regressions.
4. Format, analyze, run relevant tests, build Android APK. Never claim device behavior based on unit tests alone.
5. Update progress/security/setup documentation and commit the logical change with a descriptive conventional commit message.

Commit no credentials, local vaults, downloaded SDKs, signing material or OAuth account tokens. Public OAuth client IDs are configuration, not secrets. Provider app registrations and redirect/signing fingerprints must be configured for the eventual distributed application identity.

## Release process

After installing a signed release on an authorized USB device, run `./scripts/test-device-startup.ps1 -Device <adb-device-id>`. This restarts the app without clearing data and fails if it exits during startup. Run against the release APK: debug builds cannot expose shrinker failures in reflection-loaded Android components. WorkManager's generated Room database constructor must remain available to reflection.

Keep Android signing keys outside the repository; back them up independently. Build a signed release using local Gradle properties/environment configuration. Publish no APK as production-ready until real-device restoration, biometrics, background backup, provider errors and interrupted-write scenarios have been exercised. Record exact commands/results and remaining limitations in PROGRESS.md.

`scripts/build-release.ps1 -CreateSigningKey` creates an encrypted PKCS12 signing identity outside the repository in `%LOCALAPPDATA%/SecretsSigning` and builds an installable release APK. Its generated password is stored using Windows DPAPI, not plaintext; subsequent builds omit the switch. Preserve both the keystore and its password independently before distributing APKs. The DPAPI file can only be decrypted by the original Windows user/machine and is not itself a portable password backup. This signing identity is unrelated to vault encryption or user passphrases.

For an existing identity, set `SECRETS_KEYSTORE`, `SECRETS_STORE_PASSWORD`, `SECRETS_KEY_ALIAS`, `SECRETS_KEY_PASSWORD` in the build environment, or supply an ignored `android/key.properties` with Gradle's standard storeFile/storePassword/keyAlias/keyPassword fields. Release builds fail when signing is unconfigured; they never silently use a debug key. The local release script clears its temporary environment credentials afterward. Output is `build/app/outputs/flutter-apk/app-release.apk`.
