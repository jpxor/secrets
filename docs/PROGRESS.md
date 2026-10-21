# Implementation progress

## Manual and Google Drive backup/restore acceptance — 2026-10-20

- The maintainer reports completing both the manual backup/restore process and the Google Drive backup/restore process successfully, and explicitly requests marking that task complete. Both round-trip acceptance items are now complete in RELEASE_PLAN.md.
- Evidence is the maintainer's on-device report, not an agent-observed test. No vault contents, passphrase or provider credentials were requested or accessed. APK hash/version, device details, fresh-install/device independence and non-test-account status were not supplied, so these conditions are not inferred.
- This closes the reported manual/Drive round-trip task; safe-failure scenarios, SFTP, background/reboot, signing-key recovery and the broader release/device gates retain their existing status. No application code or production configuration changed.

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

## Passphrase policy update — 2026-10-20

- At the user's request, lowered new-vault passphrase minimum from 12 to 8 characters in both the creation dialog and crypto API. No maximum length is imposed; creation guidance recommends a longer passphrase with several random words. Existing vaults retain their original passphrases.
- Added UI and portable-recovery regression tests for seven-character rejection, eight-character acceptance, and 1,300-character passphrases without truncation. All 10 Flutter tests pass; formatting, flutter analyze and signed release verification pass.
- Updated the connected Samsung phone with adb install -r, preserving app data; the installed-release startup check passes and the app is open. APK SHA-256: bb4e0810ee7d52e52af3709cede78637093d939992bf295c1d1ddb1f95449335.

## Vault creation isolate regression — 2026-10-20

- Reproduced the reported first-vault creation failure with a regression test attaching an unsendable listener to VaultSession, as the real Flutter UI does. Isolate.run closures inside instance operations captured the session/listeners; the memory-only store tests had not exposed this.
- Moved isolate closure construction into top-level helpers accepting only passphrase and encrypted envelope arguments. Applied to creation, passphrase unlock and restore. Encryption algorithms and file format are unchanged.
- Confirmed the regression test fails before the fix (illegal unsendable isolate message) and all 11 Flutter tests pass after it, including create/lock/unlock/restore with the listener attached. No user passphrase or vault content was read or logged.
- Formatting, flutter analyze, signed release build and signature verification pass. Reinstalled on the connected phone without clearing data; physical startup check passes. User must retry creation with their own passphrase on-device; no user vault was created by automation. Replacement APK SHA-256: e73a1c4bbb83df392036c2eb4f46c80433376a3ed484a7f23aeb0641bd012547.

## Biometric binding investigation — 2026-10-20

- User reports fingerprint authentication succeeds during enrollment, then the app reports biometric key unavailable. The previous callback hid the underlying exception, and historical device logs contained no matching diagnostic.
- Moved vault-ID AES-GCM AAD submission from pre-prompt cipher initialization into the authenticated callback for enrollment and unlock. Authentication-bound Keystore keys, strong biometrics and vault-ID binding remain required. Added secret-free exception category/code-location diagnostics (never exception messages, key bytes or vault data).
- Added a physical-device regression procedure covering enrollment persistence, restart/unlock, cancellation and passphrase fallback. Physical authentication cannot be simulated by the existing host JVM tests.
- Signed release build/signature verification, five Android JVM tests, Android lint and installed-release startup check pass. Updated phone using adb install -r without clearing data. APK SHA-256: 6b72cf25345e36358655390bd536a34615850ee2e9f926707f4556f7c0524b80.
- Awaiting user's fingerprint retry on the updated app; enrollment/unlock success is not yet verified. No sanitized biometric failures have been logged since installation at the time of this entry.

## Successful biometric unlock cleanup regression — 2026-10-20

- User verified fingerprint enrollment and vault unlock now succeed after the native sequencing change, but an operation-failed snackbar appears after unlocking.
- Reproduced this in a full SecretsApp widget test with a read-only platform key buffer: the vault opens successfully, then finally-block zeroing throws UnsupportedError. Added bridge injection to test the actual application flow and verified the test fails before the fix.
- Copy platform-returned bytes into an owned mutable temporary buffer before decryption/cleanup. Continue clearing that temporary buffer; the unlocked vault holds its own independent key copy. Platform buffers remain subject to managed-runtime memory-erasure limitations already documented in SECURITY.md.
- All 12 Flutter tests pass, including the new full-app no-error-after-biometric-unlock regression. No user secrets or passphrase were accessed.
- Formatting, static analysis, signed release/signature verification and installed-device startup check pass. Updated the phone with adb install -r, preserving vault data and biometric binding. Physical fingerprint retry on this latest update is pending. APK SHA-256: 4cd19ff10026de6cc43bcbcec6252c076e616e67d55afcbc23a9e9b8016388de.

## Google Drive registration and actionable errors — 2026-10-20

- User authorized Google Drive setup and confirmed public app registration identifiers are acceptable, with all private signing keys/account credentials/tokens excluded from source. Created a dedicated Secrets Google Cloud project, enabled Drive API and configured consent branding with the user's explicitly approved support/developer contact. Prepared app-data-only scope and Android package/signing fingerprint registration; final OAuth client creation awaiting browser-required action-time confirmation.
- Added fixed-message Google authorization error mapping (cancellation, developer configuration, network, numeric unknown codes) and bounded Drive error parsing to distinguish storageQuotaExceeded from access denial/rate limits. Provider response text is never displayed, persisted or logged. Cancellation with an error-bearing result intent is still parsed to preserve the actual provider status.
- Three new native regression tests cover quota-vs-authentication classification, distinct authorization failures and suppression of private provider response text. All 12 Flutter and 8 native tests, static analysis, lint, tooling checks and signed APK verification pass. Installed updated APK preserving phone data; device startup check passes.
- Current APK SHA-256: 0cc2eea48ec1b0539321dc5153a6087122ed6093420a4f1cf218b1adad46b69d. Live Drive authorization/upload still pending completion of registration and user consent on phone. Project/contact administration does not introduce any application backend or signing-key disclosure.

## Google Cloud app identity configured — 2026-10-20

- Created the Android OAuth client after explicit action-time approval. Dedicated Secrets project has Drive API enabled, external consent in Testing, only drive.appdata scope, and the owner account present in the test-user audience. Public identity metadata is recorded in config/google-drive.public.json; support/contact/test-user personal addresses remain in Google Cloud, not source.
- Google Android client ID: 1088511768988-j094ofho34q3gk480r4pi6lbagq7ob4s.apps.googleusercontent.com. Play services identifies this app using its package and signing certificate; no client secret/service-account key/API key or google-services.json was generated or added to the APK.
- Current signed APK with improved auth/quota diagnostics is installed and verified running. User asked to connect Google Drive on-device; live authorization/upload result pending. Google UI notes configuration changes may take five minutes to several hours to propagate. Public release/branding remains future work; app is not published to a general audience.
- Live validation completed: the user confirmed Google Drive connected successfully and the vault was backed up from the physical phone. This verifies authorization and an encrypted upload using the registered signed APK; fresh-device cloud restore, token revocation and live quota-exhaustion remain separate future checks.

## Reduced public-release provider scope — 2026-10-20

- At the user's request, removed OneDrive, Dropbox and Git from setup/restore UI, native dispatch/transports and runtime dependencies. Removed AppAuth/JGit and Git-only dependencies/shrinker rules/tests; cleaned obsolete/native binary license-extraction entries. Google Drive and SFTP, local-only use and manual encrypted import/export remain.
- Removed transports are preserved in Git history. Legacy configurations fail clearly with export/reconnect guidance; local vaults, portable format, signing identity and existing remote data are preserved. No automatic destination switching or remote deletion was introduced.
- Updated UI regression coverage asserts the removed providers are absent and SFTP credentials clear across provider changes. Added native unsupported-provider coverage. All 12 Flutter and 7 native tests pass; formatting, static analysis, lint, tooling checks and git diff --check pass.
- Signed APK built and signature verified. Confirmed no JGit/AppAuth/SLF4J/JavaEWAH in releaseRuntimeClasspath and packaged native notices match source. Artifact SHA-256: 9ed91e5acca257440580cd4a762233945458a6accde47537f8f5b6b9dfe3f86c.
- Phone is no longer connected (adb devices empty); this reduced-provider APK has not been reinstalled or live Drive-retested yet. Previously confirmed Drive backup remains the baseline, not a claim of fresh-device restore validation.

## Public open-source release plan — 2026-10-20

- Wrote docs/RELEASE_PLAN.md with parallel maintainer/account/Pages and recovery/device-test tracks, explicit beta/stable gates, source-history secret review, signing/upgrade preparation, Google production setup, publication artifacts and a fallback if provider review delays general-user Drive access. No source/website/APK was published and Google remains in Testing.
- Self-hosted recommendation: retain SFTP (SSH, not FTP) now; HTTPS WebDAV is the next addition for existing Nextcloud/ownCloud/NAS users or a small authenticated TLS server. Git remains technically viable for deliberate archival but adds ciphertext history, repository/push conflicts and dependency cost without useful record-level diffs. S3 is deferred for users already running compatible storage. Do not add new protocols before releasing the tested core.
- Reduced-provider implementation is committed separately as 39b3382; the plan marks that scope work complete while leaving physical retest and the remaining launch gates open. All primary references and expected verification evidence are linked in the plan.

## Repository license inventory and settings cleanup — 2026-10-20

- Removed the settings license-screen button and its unused runtime registry setup at the maintainer's request. Kept the LICENSE/native notice assets and Flutter-generated NOTICES.Z in the signed APK; verified all three are present and nonempty. Upstream redistribution notices still accompany binary distributions.
- Added THIRD_PARTY_LICENSES.md as the consolidated component/license mapping plus full collected notices. Generation reads resolved release Maven artifacts/POMs, Dart/Flutter package licenses and native archive notices (including nested JARs). Includes Google SDK terms separately, OkHttp public-suffix/JSch subcomponents and the OpenJDK-derived desugaring source/license link. Regeneration is deterministic and contains no local absolute cache paths.
- scripts/check.ps1 -SkipBuild passes: formatting, static analysis, 12 Flutter tests, 7 Android tests, lint and tooling checks. Signed release build and APK v2 signature verification pass with the existing signing identity. First build ran out of Gradle heap; stopping its daemon and retrying with a temporary 6 GiB heap succeeded without changing committed build memory settings.
- APK SHA-256: 4af33e9ead3828675c2843a0f535a3268be00ffa33e355502e20b29c4193c336. No installation or interactive device/provider validation is claimed for this build.

## Public repository, Pages and Google preparation — 2026-10-20

- Maintainer selected GitHub account jpxor and GitHub Issues for public support. Prepared jpxor/secrets with intended Pages address https://jpxor.github.io/secrets/. No repository was created, source pushed, Pages deployed, APK/tag published or Google audience switched during preparation.
- Added buildless homepage, privacy policy and recovery/support pages in web/, plus a Pages Actions workflow that uploads only web/. Added contributor instructions, root security-reporting policy and changelog. Homepage accurately marks pre-release status, limited device evidence and unverified general-user Google availability. Privacy covers local/unlocked data, Google/SFTP metadata, retention/deletion, clipboard, biometrics, diagnostics and GitHub hosting/support.
- Added docs/PUBLIC_RELEASE_SETUP.md and config/google-production.public.json with final intended URLs, existing Android identity, scope, account/ownership steps and separate prepared-versus-live status. Inspected existing Cloud branding: Secrets, approved contacts, empty homepage/privacy URLs, Testing. Kept existing contacts in Cloud only; GitHub Issues cannot substitute for Google's required email field.
- Created the Search Console URL-prefix verification challenge for the intended Pages URL and included its public meta tag in the homepage. No ownership verification was attempted against the unpublished site. OAuth authorized-domain acceptance remains unproven; a project-path URL-prefix challenge is not proof of registrable-domain acceptance.
- History review inspected 81 historical paths and all reachable patch text for private-key headers, common GitHub/Google/AWS token signatures and sensitive file extensions/paths: zero matches. Only known public Google identity metadata is intentional. This bounded pattern review is not exhaustive secret detection or a security audit; existing Git author metadata/history will be public if published.
- OSV querybatch returned no affected results for 72 resolved Maven and direct crypto/Dart package-version queries on 2026-10-20. Not a complete vulnerability assessment; bundled engine code, proprietary Google services and every Dart transitive dependency are not covered by this result.
- Local server returned and browser rendered homepage, privacy and support; internal navigation and static local link checks pass. Desktop appearance inspected. Browser viewport override did not take effect (reported desktop dimensions), so phone-width browser verification remains unclaimed; CSS includes a mobile breakpoint and wrapping for long policy URLs.
- Required formatting, analysis, Flutter/native tests, lint, tooling checks and signed Android build passed as recorded in the preceding entry. No Android device connected (adb devices empty), so this build was not installed and physical recovery/provider checks remain open. Source-publication approval, live CI, Pages deployment/domain verification, Google review/production publishing and non-test-account recovery remain next steps.

## First public CI regression — 2026-10-20

- Published reviewed source to jpxor/secrets using the existing SSH identity. First Linux CI failed before Flutter setup: setup-android's default package list requested the retired Android SDK `tools` package. Windows signing/property checks passed.
- Replaced the default list with explicit platform-tools, Android API 36 and build-tools 36.0.0. The clean GitHub Linux workflow is the regression check for this provider/toolchain failure; rerun results will be recorded separately.

## Public source, Pages and Google production published — 2026-10-20

- With explicit maintainer approval, created public https://github.com/jpxor/secrets and pushed the reviewed history. HTTPS Git had no configured credentials; switched to the maintainer's existing, successfully authenticated SSH identity. origin is git@github.com:jpxor/secrets.git. No signing/provider credentials were generated or disclosed.
- Enabled Actions-based Pages and HTTPS enforcement. The account's existing user-site domain is inherited automatically, so the canonical project homepage is https://www.wallust.com/secrets/, with privacy.html and support.html underneath. No DNS/main-site changes were made. First successful Pages run: https://github.com/jpxor/secrets/actions/runs/39531305230 at a9288b0. All three public pages render over HTTPS; removed the unused/unverified github.io Search Console meta challenge from source.
- Enabled GitHub private vulnerability reporting, dependency graph and Dependabot alerts. Existing secret scanning/push protection remain enabled. Root SECURITY.md now links to the active private reporting route.
- Clean public Android workflow passed after the explicit-SDK-package fix: https://github.com/jpxor/secrets/actions/runs/39531268117 at a9288b0, 6m 33s. Linux Flutter formatting/analysis/tests, debug APK build and native tests/lint passed; Windows signing/password and SDK-property regression checks passed. Earlier failed run is retained as evidence of the retired-tools setup regression. Local signed release evidence/hash remains in the preceding entries; application runtime code did not change in this publication step.
- Saved Google's homepage/privacy URLs and wallust.com authorized domain, retained the existing Android OAuth identity, contacts and only drive.appdata. Published External audience to In production. Google Verification Center says sensitive/restricted scope verification is not required. Automated branding verification succeeded and Publish branding completed: Console confirms branding is verified and shown to users. Public production metadata and setup instructions reflect this observed result.
- No signed APK/tag/stable release was published. Non-test-listed-account authorization/upload, fresh-device Drive recovery and the remaining physical-device/signing-backup gates remain open; production Console status is not evidence of these tests. Public pages preserve those limitations.

## Public website copy rewrite — 2026-10-20

- Rewrote the homepage, recovery/support page and privacy policy as concise public product copy. Added the subheading "Your secrets. Your backup." and a GitHub Releases download link. Removed internal release gates, Google setup status and launch-plan links while preserving recovery requirements and privacy disclosures.
- Local page links and git diff --check pass. scripts/check.ps1 passes: formatting, static analysis, 15 Flutter tests, native tests, Android lint, tooling checks and debug APK build. The initial sandbox run encountered a Flutter temporary-file permission error; the successful run used approved execution outside the sandbox.
- Checks include unrelated application work already in progress in the shared checkout. This copy change adds no device/provider validation and does not publish an APK or deploy Pages.

## SFTP host trust confirmation and phone update — 2026-10-20

- At the maintainer's request, replaced manual SSH fingerprint entry with an SSH-style foreground trust dialog. It displays the fixed host/port and offered SHA256 fingerprint, supports cancellation, and reconnects only after explicit Trust and connect approval. The approved pin is saved with successful provider activation; saved trust is reused only for the same host and port.
- A changed key remains rejected by background backups. Foreground reconnect shows old/new fingerprints and requires a separate Trust new key decision. Key changes between approval and reconnection fail closed. Credentials are not sent to an unapproved key; connection inspection/remote-vault replacement safeguards remain unchanged.
- Added native protocol coverage for unknown-key rejection before password authentication or directory creation, successful approved-key authentication, changed-key rejection before another password attempt and explicitly approved replacement. Added host/port trust-scoping checks and widget tests for cancellation, approval/retry with unchanged credentials and changed-key cancellation. All 15 Flutter and 9 native tests pass, along with formatting, static analysis, Android lint and tooling checks.
- Signed release build and APK v2 signature verification pass with the existing signing identity. APK SHA-256: da254fe24fb45fcb96af2eaecdf896af0ba15fb425f07b4805ab6b7f2e623ff3. Installed on the reconnected Samsung SM-A546W/API 36 using adb install -r without clearing app data; installed-release startup check passes. Physical trust-dialog interaction and SFTP backup/restore are awaiting maintainer testing.
- The ignored temporary LAN-only SFTP test server now uses a shorter disposable numeric password at the maintainer's request. Its credentials/host private key are excluded from source; password handling uses memory and a DPAPI-encrypted helper input, and the server/firewall rule expire automatically. No app vault/passphrase was accessed. Separate website edits present in the working tree were left untouched.

## SFTP diagnostics and password visibility — 2026-10-20

- The maintainer reported three failed SFTP attempts with the unhelpful release-obfuscated `nw` error. A phone-side TCP check received the temporary server's SSH banner over Wi-Fi; ICMP did not respond. This establishes service reachability, not successful app authentication or backup. No separate server-test button was added, as requested.
- Added per-connection SSH stage tracking and fixed diagnostic reasons for DNS, timeout, routing/refusal, cryptographic negotiation, authentication and SFTP directory failures. Foreground guidance and background status use sanitized fixed text. Android's SecretsSftp tag records only the stage/reason code, without raw exception text/causes, credentials, endpoints or directory paths. Explicit host-key approval remains unchanged.
- Added show/hide controls for passwords and key passphrases alongside the existing private-key control. Regression tests cover field visibility without value changes and classification of nested failures without leaking synthetic private text.
- Formatting, static analysis, all 16 Flutter and 11 native tests, Android lint and tooling checks pass. Signed release build and APK v2 signature verification pass; SHA-256: 14ee5c7309c7e1126bb1283ebb9c2bf721b69a97f4c7810cb785850bd1d21ce5. Installed on Samsung SM-A546W/API 36 using adb install -r without clearing app data; installed-release startup check passes. The original SFTP failure is not yet diagnosed or claimed fixed; a new physical retry is needed to obtain its code and validate backup/restore.
