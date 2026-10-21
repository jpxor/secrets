# Secrets

An offline-first, open-source Android secrets keeper. Flutter/Dart UI and portable vault logic leave room for future iOS contributions. No application server is required.

Android implementation with automated vault/recovery, UI, backup-policy and local SFTP transport tests. Google Drive sign-in and backup have been verified on the owner's phone; fresh-install recovery and broader physical-device verification are still required before production use. See [requirements](docs/SPECIFICATION.md), [development](docs/DEVELOPMENT.md), [provider setup](docs/PROVIDERS.md), [verification checklist](docs/TESTING.md), and [security design](docs/SECURITY.md).

## Features

- Encrypted service / username / secret records; search by service only.
- Password and opaque-token generation, reveal and sensitive clipboard copy.
- Passphrase recovery and biometric-assisted unlock.
- Encrypted manual import/export and automatic backups to one selected provider: Google Drive or SFTP.
- Local-only use, durable pending backups, explicit backup status and replacement-phone recovery.

Licensed under Apache-2.0.

[Homepage](https://www.wallust.com/secrets/) ·
[Privacy policy](https://www.wallust.com/secrets/privacy.html) ·
[Recovery and support](https://www.wallust.com/secrets/support.html) ·
[GitHub Issues](https://github.com/jpxor/secrets/issues)

See [component licenses and notices](THIRD_PARTY_LICENSES.md),
[contributing](CONTRIBUTING.md), [security reporting](SECURITY.md), and
[changelog](CHANGELOG.md). Homepage/privacy/support source is in `web/`;
[publication and Google production setup](docs/PUBLIC_RELEASE_SETUP.md) records the
live URLs, account configuration and remaining validation.

## Build and run

Requires Android 8 (API 26) or newer. No Android Studio or application backend is needed.

```powershell
./scripts/bootstrap.ps1 -AcceptAndroidLicenses
. ./scripts/env.ps1
./scripts/check.ps1
flutter run -d <device-id>
```

Build a signed APK with `./scripts/build-release.ps1 -CreateSigningKey` once, then omit the switch for subsequent builds. Signing material is stored outside the repository using an encrypted PKCS12 key and Windows DPAPI-protected password. Back up the identity independently. APK output: `build/app/outputs/flutter-apk/app-release.apk`. See [development](docs/DEVELOPMENT.md) for existing identities, Linux commands, and release details.

Official Google Drive builds use the project's registered package/signing identity; forks must register their own identity. SFTP requires user-supplied connection details. OneDrive, Dropbox and Git have been removed from the initial release. The project does not ship developer account credentials. [Provider instructions](docs/PROVIDERS.md)

## Repository map

- `lib/core`: portable vault format, authenticated encryption, generation and session state.
- `lib/ui`: Flutter screens; `lib/platform`: Android bridge interface.
- `android/app/src/main/kotlin`: Android key protection, document/clipboard/lifecycle integration, WorkManager and native backup transports.
- `test` and `android/app/src/test`: focused behavior and transport regression tests.
- `docs` and `AGENTS.md`: decisions, security boundaries, verification and contributor handoff.

The Flutter UI and cryptographic format can be reused for iOS contributions; Android-native keystore, scheduling and provider integrations need iOS counterparts. Desktop and multi-device editing are outside the initial scope.

See [the public release plan](docs/RELEASE_PLAN.md) for release gates, Google production setup and the self-hosted backup assessment. No public stable release or independent security audit has been completed.
