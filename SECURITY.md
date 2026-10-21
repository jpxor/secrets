# Security policy

Secrets is pre-release software. There is no supported stable release yet and no
independent security audit has been completed. Security fixes target the current
main branch until supported release lines are announced.

## Report a vulnerability privately

Use [GitHub private vulnerability reporting](https://github.com/jpxor/secrets/security/advisories/new),
which is enabled for this repository. Do not post exploit details publicly before
maintainer coordination. If that route is unavailable, open an issue containing only
a request to establish a private reporting channel; omit vulnerability details.
No response-time guarantee is currently offered.

Never send real vaults, passphrases, provider credentials, private keys or live
secrets. Describe impact, affected version and synthetic reproduction steps.

See [the security design](docs/SECURITY.md) for threat boundaries, cryptography and
known limits, and [the release plan](docs/RELEASE_PLAN.md) for remaining validation.
