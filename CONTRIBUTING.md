# Contributing

Read [the specification](docs/SPECIFICATION.md), [security design](docs/SECURITY.md),
[development workflow](docs/DEVELOPMENT.md) and [progress](docs/PROGRESS.md) first.
Use Flutter and the Android command-line toolchain; Android Studio is not required.

Open an issue describing the problem before proposing a large feature. Keep changes
focused and use logical commits. Add regression tests for security, recovery and
reliability fixes. Run `scripts/check.ps1` and a signed release build when changing
Android/runtime behavior. Report device/provider checks separately and honestly.

Use synthetic records only. Never submit vaults, passphrases, signing material,
provider credentials or unredacted logs. Keep SDKs and local account configuration
ignored. Forks must register their own Google package/signing identity.

Changes to dependencies require updating [the license inventory](THIRD_PARTY_LICENSES.md)
and checking redistribution notices and current advisories. Contributions are made
under the repository's Apache-2.0 license. No CLA is currently required.
