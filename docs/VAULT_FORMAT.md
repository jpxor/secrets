# Secrets vault format, version 1

The portable `.secrets` file is UTF-8 JSON with three objects: `header`, `wrappedKey`, and `payload`. Provider credentials, device keys and biometric bindings are never exported. Maximum accepted portable file size is 8 MiB; application-generated plaintext payload is limited to 4 MiB.

## Header and derivation

Header fields: `format: "Secrets"`, `version: 1`, `id` (32 hexadecimal characters from 16 random bytes), `kdf: "argon2id"`, `memory: 19456` (KiB), `iterations: 2`, `parallelism: 1`, `salt` (16 random bytes, standard Base64). Version 1 readers accept exactly these KDF settings; hostile imported parameters cannot force excessive resource usage.

Derive a 32-byte wrapping key using Argon2id version 0x13 and the passphrase's UTF-8 encoding. Do not trim or normalize the passphrase. The salt is per vault. A separately generated 32-byte random data key encrypts records. Neither key nor passphrase appears in plaintext in the exported file.

## Authenticated encryption

Both encrypted objects have `nonce` (12 bytes, Base64), `mac` (16 bytes, Base64), and `data` (ciphertext, Base64). Use AES-256-GCM, a fresh cryptographically random nonce for every encryption, and the following authenticated data:

1. Serialize a JSON object in this exact order with no extra whitespace: `format`, `version`, `id`, `kdf`, `memory`, `iterations`, `parallelism`, `salt`. Values come from the header. UTF-8 encode the result.
2. For wrapped data key append UTF-8 `/key`; for encrypted records append UTF-8 `/payload`.

`wrappedKey` encrypts the 32-byte data key using the passphrase-derived wrapping key. `payload` encrypts JSON `{"records":[...]}` using the data key. Each record has string `id`, `service`, `username`, `secret`. IDs must be unique within the vault. All three user fields permit empty strings, Unicode and newlines. Authenticate before using any plaintext. Unknown fields are not application state; migrations require a new format version if semantics change.

Biometric unlock decrypts a device-local wrapped copy of the same data key with an Android authentication-bound Keystore key, then authenticates/decrypts payload as usual. New phone recovery uses only the portable wrappedKey and master passphrase.

## Android and remote wrappers

Android stores the portable envelope as a string inside an atomic JSON file with a monotonically increasing `sequence`. This is scheduling metadata, not part of the portable cryptographic format. Remote snapshots are immutable files named `secrets-<19-digit-sequence>-<16-hex-SHA256-prefix>.secrets`; contents are exactly the portable envelope. The SHA prefix is an identifier, not a substitute for AES-GCM authentication. Read-back verification precedes backup acknowledgment.

New installations inspect remote files before activation and restore/decrypt before enabling writes to another vault's destination. Restoring an older retained snapshot is supported through the provider restore chooser. Android sequence advancement accounts for a new phone with an earlier clock. This is single-device backup/recovery, not a distributed merge protocol.
