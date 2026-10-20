# Security design

## Boundaries

Protect persisted vault contents and remotely stored backups from disclosure/tampering without the master passphrase. Android sandboxing and authentication-bound Keystore keys support local protection. An unlocked/compromised OS, malicious keyboard, or modified application can observe plaintext; the project does not claim protection against those.

## Portable envelope

Use a random vault data key with authenticated encryption, wrapped by a passphrase-derived key. Version the format, KDF parameters and authenticated headers. Use fresh random nonces, a memory-hard password KDF, bounded input sizes/parameters to resist malicious-file resource exhaustion, and established crypto implementations. Authenticate before parsing payloads or changing local state. Portable envelope includes everything required to restore with the passphrase and excludes provider credentials and device-only keys.

Implemented algorithms are Argon2id (19 MiB, 2 iterations, 1 lane) and AES-256-GCM via cryptography 2.9.0. See VAULT_FORMAT.md for byte-level interoperability details. Android system/cloud device transfer of app state is disabled: portable export or the configured backup provider is the supported recovery route.

## Local state

Only encrypted envelopes and non-secret scheduling metadata are stored in app-private files. Device biometric binding wraps the vault data key using an Android Keystore key requiring strong biometric authentication. Do not store the master passphrase. Locking drops references to plaintext state/key bytes on a best-effort basis; managed runtimes cannot promise complete RAM erasure.

## Backups

Background workers upload encrypted envelopes without unlocking the vault. Provider credentials are encrypted under a separate device Keystore key (not biometric-bound, so background jobs work). Use TLS with normal certificate verification and pinned SSH host keys. Never disable host verification. Failures must not erase pending work. A new installation cannot infer ownership of an existing remote vault and must explicitly restore or replace it.

## Review requirements

Test wrong passphrases, tampering, format bounds, replacement-phone recovery, stale upload ordering, interrupted persistence and failed retries. Native biometric binding, clipboard replacement and screen locking need real-device checks. No security audit has yet been performed.
