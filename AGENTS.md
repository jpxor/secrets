# Development handoff

Read docs/SPECIFICATION.md, docs/SECURITY.md, docs/DEVELOPMENT.md and docs/PROGRESS.md before changing this application.

- Keep changes in logical Git commits. The user explicitly requested incremental feature commits.
- Do not log, commit or write plaintext vault values, passphrases, provider credentials, or private keys to disk.
- Use established cryptographic libraries; biometric success alone must never act as the vault encryption key.
- No silent upload of an empty/new vault over an existing backup. Import replaces, and requires confirmation for a populated local vault.
- Keep background backups independent of access to decrypted vault data.
- Test difficult security/reliability behavior and add a regression test whenever a regression is fixed. Avoid implementation-mirroring tests.
- Run formatting, static analysis, relevant tests and an Android build before claiming a change is complete. Record any unavailable device/provider checks honestly.
- Keep provider secrets and SDK downloads ignored. Never put an OAuth client secret in an APK.
- No Android Studio, no application backend, and no deployment unless requested.
