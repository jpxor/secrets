# Development process

## Environment

Use Flutter stable, a compatible JDK and Android command-line SDK. Android Studio is not required. Tool downloads go in ignored `.tools/`; no global PATH changes are necessary. Use a real Android device with USB debugging for biometric, screen-lock and background-execution verification. Apple builds require a contributor with macOS/Xcode.

## Workflow

1. Read specification/security/progress documents and inspect `git status`.
2. Implement one logical feature, keep platform APIs behind interfaces.
3. Add tests for important boundaries (authenticated encryption, recovery, backup ordering/failures) and regressions.
4. Format, analyze, run relevant tests, build Android APK. Never claim device behavior based on unit tests alone.
5. Update progress/security/setup documentation and commit the logical change with a descriptive conventional commit message.

Commit no credentials, local vaults, downloaded SDKs, signing material or OAuth account tokens. Public OAuth client IDs are configuration, not secrets. Provider app registrations and redirect/signing fingerprints must be configured for the eventual distributed application identity.

## Release process

Keep Android signing keys outside the repository; back them up independently. Build a signed release using local Gradle properties/environment configuration. Publish no APK as production-ready until real-device restoration, biometrics, background backup, provider errors and interrupted-write scenarios have been exercised. Record exact commands/results and remaining limitations in PROGRESS.md.
