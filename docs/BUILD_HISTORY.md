# How Secrets was built

The first prompt, October 19, 2026 (wording preserved; blank lines condensed):

> work with me to develop the specifications for a new secrets keeper app called "Secrets".
>
> my current requirements:
>
> 1. accessible on my phone and on my desktop
> 2. synced between all devices
> 3. no server costs or complex server set (preferably, real serverless).
> 4. need to keep list of [service, username, secret].  secret is hidden, but can be viewed, copied, or updated. all fields are free-form text
> 5. can add or delete secrets
> 6. can generate random secret when requested (password style or bearer token style)
>
> i was originally thinking of keeping secrets saved on a remote git server, and app pulls and pushs.  but not sure if this is possible on the phone?  how can we let users use free hosting anywhere they have access to?

Codex proposed a PWA with Git-backed storage. The user's next prompts added encryption and fingerprint unlock, then changed the scope: “maybe we change focus and make this single device, phone only.” That replaced synchronization with an offline Android vault and encrypted backups.

“if the user gets a new phone, we need to be able to load and decrypt the backup” drove the key design: a portable passphrase-protected vault, with biometrics providing convenient access on the current phone. Requiring backup whenever local data changes added automatic queuing and retries; manual export/import remained available.

Prioritizing multiple phone operating systems led to Flutter/Dart; lacking macOS/Xcode narrowed delivery to Android. “no android studio” established command-line development. Numbered answers settled local-only setup, replacement imports and service-only search. The scrolling concern made automatic locking background-only.

The implementation prompt required logical feature commits, focused tests, regression coverage and a documented handoff. The resulting [specification](SPECIFICATION.md), [security design](SECURITY.md) and [workflow](DEVELOPMENT.md) guided incremental development and phone testing.

Later prompts made three substantial changes:

- **Backup scope:** full Drive storage prompted five providers; prioritizing public release later removed OneDrive, Dropbox and Git, retaining Drive, SFTP and manual files.
- **Ordinary-user setup:** “i want any user to just sign into their account” moved cloud app registration from user setup to the maintainer's responsibilities.
- **SFTP usability:** “entering the ssh host finger print is terrible ux” replaced manual entry with a trust-and-pin dialog. The requirement that server owners solve their own connection problems led to actionable diagnostics.

After confirming backup and restore worked, the user requested merging the changes and creating a release. **0.1.0-beta.1** followed on October 21.

Based on the available project chats and Git history; technical detail remains in [the progress log](PROGRESS.md).
