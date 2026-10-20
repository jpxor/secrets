# Product specification

## Decisions

Secrets is a single-device, Android-first Flutter/Dart application. Source is Apache-2.0. APK distribution first. Future iOS/desktop contributions are possible but not current deliverables. Build without Android Studio using JDK, Android CLI SDK and Gradle.

One vault per installation. Each record has an internal ID and three free-form, multiline text fields: service, username, secret. Duplicate service names are allowed. Add/edit/delete; deletion confirms. Search service only, never username. Reveal and copy require no additional authentication while unlocked. Cryptographically secure configurable password and opaque token generation. No attachments, sharing, autofill service or simultaneous multi-device editing in v1.

Encrypt all persistent vault content, including service and username. Master passphrase unlock and recovery; optional biometric unlock via device-protected key. No separate recovery key in v1. Forgotten passphrase cannot be reset by the project. Never persist plaintext vault data or passphrase. Lock immediately on phone lock, or after 30 seconds continuously in background (configurable); foreground scrolling/reading never triggers inactivity locking. Treat copied secrets as sensitive and clear after 30 seconds only if not replaced.

## Backup and recovery

Local-only setup is supported; backup can be added later. Exactly one active provider: Google Drive, OneDrive, Dropbox, SFTP, or standard Git over HTTPS/SSH. Every committed local change immediately queues an encrypted backup. Upload promptly online; durable retries offline or after failures, with Android scheduling limits. Show backed-up/pending/needs-attention and last successful backup time. Serialize uploads; never let old snapshots overwrite new ones. Interrupted writes retain the last valid remote backup. Keep a small bounded history of encrypted snapshots; Git/provider history may retain additional older copies.

Provider credentials remain separate from portable vault exports. New phone restoration requires provider access and the master passphrase, not the old phone or biometric key. Fresh setup offers restore before creation. Never silently replace remote data. SSH/SFTP host keys must be pinned and changes explicitly approved.

Manual encrypted export/import is always available independently of the provider. Import replaces (does not merge) local vault; warn when existing vault has records. Authenticate/decrypt an import before replacing any local state. A successful restore must establish a new local biometric binding if enabled.

## Defaults

- 30 seconds in background before locking; phone lock is immediate.
- 30 seconds before clipboard clearing, without clearing newer content.
- Retain 5 encrypted backup generations where the provider supports pruning; do not rewrite Git history.
- Search only service, case-insensitively.
- Master passphrase is required, biometrics optional.
