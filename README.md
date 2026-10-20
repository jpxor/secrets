# Secrets

An offline-first, open-source Android secrets keeper. Flutter/Dart UI and portable vault logic leave room for future iOS contributions. No application server is required.

Status: implementation in progress. See [requirements](docs/SPECIFICATION.md), [development](docs/DEVELOPMENT.md), and [security design](docs/SECURITY.md).

## Intended features

- Encrypted service / username / secret records; search by service only.
- Password and opaque-token generation, reveal and sensitive clipboard copy.
- Passphrase recovery and biometric-assisted unlock.
- Encrypted manual import/export and automatic backups to one selected provider: Google Drive, OneDrive, Dropbox, SFTP, or generic Git (HTTPS/SSH).
- Local-only use, durable pending backups, explicit backup status and replacement-phone recovery.

Licensed under Apache-2.0.
