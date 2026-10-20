# Secrets

An offline-first, open-source Android secrets keeper. Flutter/Dart UI and portable vault logic leave room for future iOS contributions. No application server is required.

Android implementation with automated vault/recovery, UI, backup-policy and local SFTP/Git transport tests. Physical-device and live cloud-account verification are still required before production use. See [requirements](docs/SPECIFICATION.md), [development](docs/DEVELOPMENT.md), [provider setup](docs/PROVIDERS.md), [verification checklist](docs/TESTING.md), and [security design](docs/SECURITY.md).

## Features

- Encrypted service / username / secret records; search by service only.
- Password and opaque-token generation, reveal and sensitive clipboard copy.
- Passphrase recovery and biometric-assisted unlock.
- Encrypted manual import/export and automatic backups to one selected provider: Google Drive, OneDrive, Dropbox, SFTP, or generic Git (HTTPS/SSH).
- Local-only use, durable pending backups, explicit backup status and replacement-phone recovery.

Licensed under Apache-2.0.

## Build and run

Requires Android 8 (API 26) or newer. No Android Studio or application backend is needed.

```powershell
./scripts/bootstrap.ps1 -AcceptAndroidLicenses
. ./scripts/env.ps1
./scripts/check.ps1
flutter run -d <device-id>
```

Build a signed APK with `./scripts/build-release.ps1 -CreateSigningKey` once, then omit the switch for subsequent builds. Signing material is stored outside the repository using an encrypted PKCS12 key and Windows DPAPI-protected password. Back up the identity independently. APK output: `build/app/outputs/flutter-apk/app-release.apk`. See [development](docs/DEVELOPMENT.md) for existing identities, Linux commands, and release details.

Google Drive requires a Google OAuth registration for this package/signing identity. OneDrive and Dropbox require public OAuth application IDs, supplied in the setup screen or via Dart build configuration. SFTP/Git require user-supplied connection details. The project does not ship developer account credentials. [Provider instructions](docs/PROVIDERS.md)

## Repository map

- `lib/core`: portable vault format, authenticated encryption, generation and session state.
- `lib/ui`: Flutter screens; `lib/platform`: Android bridge interface.
- `android/app/src/main/kotlin`: Android key protection, document/clipboard/lifecycle integration, WorkManager and native backup transports.
- `test` and `android/app/src/test`: focused behavior and transport regression tests.
- `docs` and `AGENTS.md`: decisions, security boundaries, verification and contributor handoff.

The Flutter UI and cryptographic format can be reused for iOS contributions; Android-native keystore, scheduling and provider integrations need iOS counterparts. Desktop and multi-device editing are outside the initial scope.
