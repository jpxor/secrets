# Verification and release checklist

## Automated checks

Run `scripts/check.ps1` from PowerShell after setting up local tools. It formats/checks Dart, runs `flutter analyze`, Flutter tests, Android JVM backup reliability tests, Android lint, and builds a debug APK. `-SkipBuild` skips only the final APK build. Signed release builds also run APK signature verification and produce a SHA-256 checksum.

Tests cover:
- Portable recovery, wrong passphrases, authenticated tamper rejection and hostile KDF bounds.
- Failed saves/imports preserve existing data; corrupt storage cannot be treated as a fresh installation.
- Locking is based on background duration, never foreground inactivity.
- Password character policies and token byte counts.
- Service-only search and fresh-install restore choices.
- Interrupted uploads, preservation of prior snapshots, idempotent retry after process death, stale/foreign-vault rejection.
- Real loopback SFTP upload/read/delete with server-key pinning.
- Release provider selection exposes only Google Drive/SFTP; native setup rejects removed providers and provider switching clears credentials.
- Background lifecycle events cannot extend the original lock deadline; switching away from and back to SFTP clears credentials.
- Windows signing password DPAPI round-trip, including newline handling (PowerShell check).
- Windows SDK-property escaping and idempotence (PowerShell check).

When a regression is found: reproduce it with the smallest behavior-level test, confirm failure, fix it, run the relevant checks, and record the regression in PROGRESS.md. Avoid tests that only repeat implementation details.

## Physical Android device

1. Install using `adb install -r build/app/outputs/flutter-apk/app-debug.apk` with an authorized USB-debugging device.
2. Create a vault, add multiline/Unicode records, generate both secret styles, search only service, reveal/copy/edit/delete.
3. Enable biometric unlock, lock, unlock with fingerprint, cancel the prompt, change enrolled fingerprints and verify passphrase fallback.

   Biometric binding regression: on the signed release, unlock an existing vault with its passphrase, enable biometrics and authenticate. The switch must remain on without a key-unavailable error. Restart the app, use fingerprint unlock and verify a known test record. Cancel enrollment and verify passphrase unlock still works. Exercise this on a physical Samsung/API 36 device: host JVM tests cannot reproduce authentication-bound Keystore operations. Vault-ID AAD must be supplied to the authenticated cipher after successful fingerprint authentication, before doFinal; do not remove AAD or disable key authentication to work around failures.
4. Scroll/read for more than 30 seconds: remain unlocked. Background 29 seconds: remain unlocked; 30 seconds: lock. Phone screen off: lock immediately. Verify screen captures/recents do not expose records.
5. Copy a secret, replace clipboard with a different value, wait 30 seconds: newer content survives. Repeat without replacement; check best-effort clearing, including OS background restrictions.
6. Export encrypted file, clear app data or install on another device, restore with passphrase. Wrong passphrase/tampering must preserve current vault. Import populated vault warns. Verify restored records before relying on backup.

The signed release uses a different signing identity from debug builds. If Android rejects installing one over the other, export the vault before uninstalling the old build; uninstalling removes local app data. Reimport and confirm records after installing the replacement.

## Each remote provider

Use disposable test accounts/directories; never real secrets during initial validation. Test connect to empty destination, edit/upload, offline edits, app restart, reconnect, expired authorization, full storage, interrupted upload, retention and fresh-install recovery. Inspect remote bytes for plaintext. For SSH, reject unknown/wrong host keys.

Cloud registrations, account credentials and a physical Android device are external dependencies. Passing unit/widget tests is not evidence these end-to-end checks passed. Update PROGRESS.md with actual results before labeling an APK ready for production secrets.
