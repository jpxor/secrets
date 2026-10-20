# Implementation progress

Current status: Android application implemented, signed APK built and verified. Final combined checks pass. See the final handoff section for remaining external validation.

## Initial state

Empty workspace, no Git repository or Flutter/JDK/Android SDK on PATH. User authorized installing necessary development tools. SDKs are being installed locally in `.tools/`.

## Commit plan

1. Generated Flutter/Android framework, documented requirements and contributor workflow.
2. Portable authenticated vault, generation and persistence, focused recovery/tamper tests.
3. Android key protection, lifecycle locking, clipboard and encrypted file transfer.
4. Durable automatic backup and five provider adapters, reliability tests.
5. Complete application UI, setup/recovery flows, integration, build and handoff.

External OAuth registrations, remote test accounts and an attached Android phone may require user-supplied configuration. Record actual verified results and limitations below as implementation progresses.

## Framework and portable vault

- Installed Flutter 3.47.7 / Dart 3.13.5, Temurin JDK 17.0.20.1, Android command-line tools, API 36 and build tools 35 locally; no Android Studio.
- Initial framework committed as `93eec0a`.
- Added versioned Argon2id (19 MiB, 2 iterations) / AES-256-GCM envelope, independent data key, authenticated metadata, bounded decoding, secure password/token generation, serialized session operations and background-only locking.
- `flutter test test/vault_test.dart test/session_test.dart --reporter expanded`: 3 tests passed. Covers fresh-device recovery, wrong passphrases, tampering/KDF bounds, failed-save/import preservation and foreground/background timing.

## Android and transport implementation

- Android minimum API 26 (Android 8) to support the Java NIO APIs needed by generic Git. Targets API 36.
- First debug APK built successfully. Real phone not connected (`adb devices` returned an empty list).
- Added encrypted device-local provider configuration, native biometric CryptoObject wrapping, FLAG_SECURE, screen-off lock signal, sensitive clipboard handling and SAF encrypted import/export.
- Added WorkManager queue/reconciliation, immutable encrypted snapshots, verification before acknowledgment, bounded history, remote-vault/conflict protection and adapters for all five providers.
- Six Flutter tests pass, including service-only search, restore-first setup and a regression preventing Create from overwriting unreadable storage.
- Local SFTP integration test passes (real loopback SSH server, upload/download/delete and bad host-key rejection). Backup interruption/idempotence/conflict JVM tests pass.
- Generic Git SSH push/clone/restore succeeded in its first integration run, but the final cleanup assertion failed on Windows read-only Git pack files. Added symlink-safe NIO cleanup that removes read-only cache files; the integration test is retained as regression coverage.
- Cloud OAuth registrations and physical-device biometric/background checks remain external validation requirements; no claim of those checks passing.

## Resumed verification

- After the earlier approval-review usage limit, the user asked to continue. Normal elevated execution resumed successfully.
- All four Android JVM tests now pass, including the Git cleanup regression. Six Flutter tests and static analysis pass.
- Recovery/native integration and application UI committed separately as `0b642ae` and `cb69d5f`; backup feature is `b50869c`.
- Added a regression test for repeated background lifecycle events extending the lock deadline; confirmed it failed before changing the timer to preserve the original deadline.
- Queried OSV for the pinned direct cryptography/JGit/JSch/OkHttp/AppAuth dependencies: no vulnerabilities returned. This limited dependency check is not a security audit or a complete transitive-dependency assessment.
- Added and confirmed a failing UI regression test for credentials carrying from SFTP into Git when changing the provider selector. Provider changes now clear credential fields; private-key inputs are masked by default.
- First release shrinking identified optional desktop-only JGit ProcessHandle/JMX/Kerberos classes. Added narrow missing-class rules, disabled automatic GC in temporary clones, used preemptive HTTPS Basic authentication and preserved reflection-loaded JSch implementations. Added checked Bouncy Castle 1.86 for modern SSH algorithms on older Android. Debug builds alone would not have exposed the release shrinker issue.
- Signed-release tooling creates its encrypted PKCS12 identity outside the repository at `%LOCALAPPDATA%/SecretsSigning`. Fixed a DPAPI text newline parsing failure and added a passing PowerShell regression check. No signing passwords or private keys are committed.
- Signed release built successfully (50.4 MiB as reported by Flutter), APK v2 signature verified. Package `app.secretskeeper.secrets`, API 26 minimum / API 36 target, ARM64/ARMv7/x86_64 included. Native notice asset matches source; release seeds retain the backup worker and reflection-loaded SSH implementations.
- Final analysis and 8 Flutter + 4 Android tests pass. Android lint initially rejected Flutter-generated Windows local.properties drive-colon escaping (2 errors); added an idempotent normalizer with a regression self-test before lint. Other lint findings are warnings (dependency updates, style/resource suggestions and JGit's optional trust-all implementation, which normal TLS-verifying transport does not select).
- Added an HTTPS regression test using a temporary self-signed local TLS server: Git rejects the certificate before sending credentials. It passes.
- A combined rerun exposed an intermittent Windows Git pack-file handle retained after repository close. Explicitly reset JGit's pack cache (with JMX and memory mapping disabled) before symlink-safe deletion, with short bounded file-lock retries. Also reproduced username persistence in temporary Git configuration; sanitize user-info from persisted remote URLs and inject SSH credentials in memory. Existing Git integration tests now assert credential absence and cleanup.

## Final handoff — 2026-10-20

- Application-source commit: `e0cb114`. Features and fixes were committed in logical increments after the framework commit. No repository remote was configured or source published.
- `scripts/check.ps1 -SkipBuild` completed successfully: formatting, `flutter analyze` (no issues), 8 Flutter tests, 5 Android JVM tests, Android lint (no errors; warnings remain), signing DPAPI regression check and SDK-property escaping regression check.
- The Git SSH round-trip/credential-metadata/cache-cleanup regression passed three consecutive forced reruns, followed by the full suite. The HTTPS test rejects an untrusted local certificate before sending credentials.
- `scripts/build-release.ps1` completed successfully after the final application fixes. Artifact: `build/app/outputs/flutter-apk/app-release.apk` (52,883,313 bytes). APK Signature Scheme v2 verification succeeds; release is not debuggable. API 26 minimum, API 36 target, ARM64/ARMv7/x86_64.
- Release SHA-256: `7def2828e6076045ec6f1613ea83441510afbde75b4937e6baef0ff0c551390f`. Companion checksum/signing reports are alongside the APK. These files are ignored build output, not source assets.
- Signing certificate SHA-1 for this local release identity: `b3007c64751db0806c6d4da1f1e1029ccf9f924b`. Public package/signature registration details can be used for Google OAuth setup. Private signing material is outside the repository under `%LOCALAPPDATA%/SecretsSigning`, with its password protected by Windows DPAPI.
- SDKs/JDK/caches are local in ignored `.tools/`; Android Studio was not installed. Reproducible Windows bootstrap, checks, signed builds and CI configuration are included.

### Still requires external validation

- No Android phone was connected (`adb devices` empty). Physical fingerprint/key-invalidation, screen locking, clipboard behavior, background scheduling/reboot and full device-to-device recovery must follow docs/TESTING.md before production use.
- Google OAuth package/signing registration and OneDrive/Dropbox public app registrations are not supplied. Cloud adapters are implemented; live account authorization, quota/error handling and fresh-phone cloud restoration have not been exercised. See docs/PROVIDERS.md. SFTP and Git SSH were tested against local real protocol servers; external hosts and Git HTTPS authentication need live-account checks.
- No independent security audit has been performed. Lint dependency-update/style/resource warnings and optional JGit TLS-manager implementation warnings remain; actual configured HTTPS certificate rejection is covered by a passing test. No certificates/SSH host keys are silently trusted.

## Physical-device installation — 2026-10-20

- Installed the signed release on a Samsung Galaxy A54 (SM-A546W), Android API 36. First physical launch exposed an R8 regression: WorkManager could not reflectively construct WorkDatabase_Impl, so the app crashed before showing its UI.
- Preserved public no-argument constructors on RoomDatabase subclasses. Added scripts/test-device-startup.ps1 to restart the installed APK without clearing data and check that its process survives startup. Confirmed this regression check fails on the original release and passes after rebuilding and reinstalling the fixed release.
- Signed release build/signature verification, Dart formatting, flutter analyze and git diff --check pass. Installed successfully with adb install -r and opened on the phone. Existing app data was not cleared. Biometric, backup, vault-recovery and other interactive device checks remain pending user testing.
- Replacement APK SHA-256: c3a6e00ea2cab0d4c37703dd181b5f84e89055a44ea9382ca29d2abcc42e9e7d. Signing identity is unchanged. This artifact supersedes the checksum in the earlier handoff above.
