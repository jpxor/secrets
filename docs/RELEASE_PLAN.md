# Fast public open-source release plan

Updated 2026-10-20. Target the smallest honest public beta, then a stable release after recovery and operational evidence. Execute the two release tracks in parallel and defer new features. Provider review is an external dependency, so the gates below determine readiness rather than a promised date.

## Release scope and current evidence

- Android APK first, Android 8+; Flutter/Dart, Apache-2.0, no application backend or Android Studio.
- Offline vault, biometric/passphrase unlock, record editing/search/generation, encrypted manual export/import.
- Exactly one optional backup destination: Google Drive or SFTP. Local-only is supported. OneDrive, Dropbox and Git are removed from the app, native transports and their unused dependencies. Prior implementations remain in Git history.
- Keep the existing package, signing identity and portable vault format. Existing Google backups must restore in the release. Never reset the user's phone to test recovery.
- The maintainer confirmed successful end-to-end manual and Google Drive backup/restore on 2026-10-20; that acceptance task is complete. Full automated checks are available. Separate fresh-device/non-test-account conditions, sustained background/reboot behavior and the broader physical-device matrix were not specified in that report and remain unclaimed.
- OneDrive/Dropbox registrations, Git, WebDAV, S3, iOS, desktop, sync, autofill and a Play Store launch are outside the first release.

## Execution order

| Priority | Work | Owner | Completion evidence |
| --- | --- | --- | --- |
| P0, complete | Freeze the reduced provider scope; remove unused code/dependencies, update docs and reject legacy provider configurations clearly | Development | Commit `39b3382`; 12 Flutter + 7 native tests, full checks and signed APK pass; phone disconnected, so this build still needs device retest |
| P0, complete | Choose GitHub repository/owner and GitHub Pages address; confirm public support/security-reporting contacts | Maintainer | jpxor/secrets; https://www.wallust.com/secrets/; Issues and GitHub private vulnerability reporting |
| P0, complete | Prepare and publish homepage, privacy policy, support/recovery guide and release limitations | Development + maintainer | Live Pages site verified over HTTPS; see PUBLIC_RELEASE_SETUP.md |
| P0, complete | Validate manual and Google Drive backup/restore | Maintainer-assisted device testing | Maintainer confirmed both backup/restore round trips successful on 2026-10-20; see PROGRESS.md |
| P0 | Complete recovery failure cases and remaining device acceptance conditions | Maintainer-assisted device testing | Safe-failure, fresh-device independence, SFTP and broader device checks below; successful round trips alone do not establish these conditions |
| P0 | Review security-sensitive paths and release dependencies; fix discovered data-loss/authentication bugs | Development + another reviewer where available | Findings closed or explicitly assessed; no known data-loss/authentication-bypass issue |
| P0, configuration complete; live validation open | Finish Google production branding/audience setup against the final Pages URLs | Maintainer-assisted account setup | External/In production, branding verified/published; non-test-account authorization/upload/restore remains unverified |
| P0 | Secure and prove the release signing/upgrade process | Maintainer + development | Recoverable key/password backup and successful data-preserving upgrade |
| P0 | Publish source and a tagged, signed beta with checksums and limitations | Maintainer-approved publication | Repository, release tag, source commit, signed APK, checksum and CI results agree |
| P1 | Observe beta feedback, resolve regressions and promote the tested build to stable | Maintainer + testers | Stable-release gate below |

The account/Pages/Google track and device-test track should proceed in parallel. Do not add another provider while they run. If Google production approval is delayed, source can still be public and an explicitly labelled local/manual/SFTP beta can ship; do not advertise general-user Drive availability while it remains limited to test users. Keep Google availability accurately explained in the release notes and app before using this fallback.

## Recovery and device acceptance gate

Use disposable records and a test passphrase entered by the tester on-device. Record APK version/hash, phone model, Android version, expected/actual result and pass/fail in a release test report. Test the signed release, not only a debug build.

1. Create a vault, add/update/delete a record, generate both secret styles and search by service only. Verify stored/remote envelope inspection using synthetic data does not reveal any of the three fields.
2. Upload to Google Drive. Restore on a fresh independent installation with the account and passphrase, without the old phone or its Keystore. Compare all synthetic records; enable a fresh biometric binding. Do the same with manual export/import and SFTP if SFTP is advertised as verified.
3. Wrong passphrase, tampered/truncated export, interrupted write, populated-vault replacement cancellation and a foreign remote vault must preserve existing local/remote data. Establish the expected backup history and retention behavior.
4. Fingerprint enrollment, unlock, cancellation, changed enrollment and passphrase fallback work. Foreground use never locks by inactivity. Background deadline and screen-off locking work. Screenshots/recents hide contents; clipboard cleanup preserves newer clipboard contents.
5. Make an offline change, restart the app and reboot the device, reconnect, then verify the newest saved snapshot uploads. Verify Android scheduling limits are accurately described; queued work must not disappear.
6. Revoke Google authorization, simulate full storage/rate limiting and interrupted upload, then reconnect/retry. Show correct status and retain the prior valid backup. For SFTP reject changed/unknown server keys and verify unavailable-server recovery.
7. Install a newer APK with the same signing identity over an existing synthetic vault. Verify records, passphrase, biometric binding, provider configuration and pending work survive. Test at least the owner's device and an additional Android/API configuration; record untested Android versions plainly.

These are release tests, not a request to clear the owner's current app data. Manual and Google Drive backup/restore round trips are complete by maintainer confirmation. The report did not specify a fresh installation, independent device, non-test-listed account, APK hash or device details; do not infer those conditions or completion of the failure-case matrix.

## Public repository and release operations

- Confirm repository name/owner and visibility with the maintainer. Review all history for credentials, signing keys, vaults and personal data before publication; ignoring a file now does not remove historical commits. Public OAuth IDs and certificate fingerprints are expected public configuration.
- Keep Apache-2.0 LICENSE and correct third-party notices. Publish CONTRIBUTING instructions, a private vulnerability-reporting route/SECURITY policy, supported versions and a short changelog. Use GitHub private vulnerability reporting or an approved security contact; never ask users to attach real vaults/passphrases in public issues.
- Publish a minimal homepage and privacy policy on GitHub Pages. Describe exactly what goes to Google/SFTP, device-local credential handling, encrypted backups, retention/deletion limits, recovery requirements and the absence of a maintainer-operated data server. Do not claim zero collection by third-party providers or an independent audit that has not happened.
- Run CI from a clean checkout and verify documented CLI bootstrap. Run `scripts/check.ps1 -SkipBuild`, `scripts/build-release.ps1` and the device startup/recovery checks. Review runtime dependency/license inventory; use a current dependency advisory check.
- Preserve the existing encrypted APK signing key and a separately recoverable password backup. The Windows DPAPI file alone is not a portable password backup. Keep all signing material outside the public repository. Continue signing locally initially; do not introduce CI signing credentials just to launch faster.
- Set a beta version/build number (proposed `0.1.0-beta.1+2`, after checking published build numbers), monotonically increment build numbers, tag the exact source commit and attach the verified signed APK plus SHA-256 checksum to GitHub Releases. Explain installation/update steps, Android/API support, backup restore, forgotten-passphrase consequences and current limitations.
- Public-source publication does not require Google OAuth production approval. General-user Google-backed APK distribution does require completing its applicable consent/branding requirements. Review current Android developer-verification rules for intended distribution channels/regions; a Play Store account/listing is not part of APK-first delivery.

## Google production configuration

Published repository/Pages URLs and saved Google production configuration are in
[PUBLIC_RELEASE_SETUP.md](PUBLIC_RELEASE_SETUP.md). Branding is verified/published;
general-user authorization and fresh-device recovery remain separate validation.

- Use the existing registered release package/signing fingerprint. Prepare separate development/test registration with a debug identity for future work; do not replace the release signing key or silently redirect existing backups to a different app identity.
- Finish homepage/privacy policy and any required terms/support/authorized-domain information in Google Auth Platform. Verify ownership of domains where required; validate whether the chosen GitHub Pages URL meets Google's ownership checks before committing to it. A custom domain, if required, is a maintainer cost decision, not an application server.
- Keep only `drive.appdata`, classified by Google as non-sensitive. Complete the applicable branding/review process and publish the audience when ready. Do not assume non-sensitive means all publishing requirements disappear.
- Test a Google account absent from the test-user list, including consent, upload and fresh-install recovery. Confirm continued background authorization after app restart and appropriate reauthorization after revocation.

## Self-hosted backup assessment

SFTP uses SSH, not FTP. It is the release recommendation for users who already have SSH access: one restricted account/directory, a password or SSH key, and a verified server fingerprint. It needs no OAuth app registration. Operating a server still has hardware/hosting, security and maintenance costs for its owner; Secrets does not operate it.

| Option | Fit for Secrets | Decision |
| --- | --- | --- |
| SFTP | Existing implementation, ordinary SSH servers/NAS, encrypted transport, explicit host-key pinning; connection details are less familiar to casual users | Keep for the first release and validate a real external host |
| HTTPS WebDAV | URL + username + app password; works with existing Nextcloud/ownCloud/NAS installations; standard file operations and HTTPS port | Best next self-hosted option, after release; not implemented now |
| S3-compatible object storage | Good snapshot/versioning model and restricted bucket credentials; more endpoint/bucket/region/access-key configuration and request-signing complexity | Later, for users already running compatible storage |
| Git | Useful when an existing repository is already the user's preferred durable archive; adds branches/cloning/push conflicts and history maintenance | Remove now; not the default recommendation for this vault |
| Custom Secrets server | Could offer a tailored API but creates a service/protocol and ongoing maintenance obligation | Do not build for v1 |

Why remove Git: the app encrypts whole snapshots with fresh nonces, so ciphertext changes do not produce useful record-level diffs or merges. Each commit largely adds another encrypted blob. Deleting a current file does not remove copies reachable in history, so five visible snapshots do not mean five stored copies. Git's history is a benefit for deliberate archival, but it complicates retention and recovery UX for ordinary users. It is technically viable; it is unnecessary release risk here. The removed implementation is recoverable from source history.

WebDAV follow-up requirements: HTTPS with normal certificate validation, dedicated app password where available, bounded responses, safe path handling and no cross-origin credential forwarding. Use immutable encrypted snapshot names, interrupted-upload safety, deterministic latest selection, retention and foreign-vault protection; verify create/move/conditional-write behavior against each supported server rather than assuming all WebDAV servers behave identically. Test Nextcloud and one small standalone server before claiming compatibility. Existing Nextcloud users can use its app passwords; someone hosting only Secrets should not need a full Nextcloud deployment. A standalone server such as `rclone serve webdav` can serve an existing directory with TLS and authentication, but requires administration. No WebDAV implementation work should delay the initial release.

## Stable-release gate and deferred work

Stable follows a beta with no unresolved data-loss/authentication-bypass findings, repeatable fresh-device recovery, working upgrade/backup after restart and feedback on more than the original phone. Obtain an independent security-focused code review; a formal external audit is desirable, but do not imply a paid audit has occurred or make beta publication depend on buying one. Document review coverage and remaining limitations.

Defer OneDrive/Dropbox, Git, WebDAV/S3, iOS/desktop, autofill, multi-device editing, account systems, telemetry and additional infrastructure. Revisit after the core recovery path is proven.

## Primary references

- [Google app-data scope](https://developers.google.com/workspace/drive/api/guides/appdata)
- [Google branding and production requirements](https://developers.google.com/identity/protocols/oauth2/production-readiness/brand-verification)
- [Android developer verification](https://developer.android.com/developer-verification)
- [Nextcloud WebDAV file operations](https://docs.nextcloud.com/server/stable/developer_manual/client_apis/WebDAV/basic.html)
- [Nextcloud app-password access](https://docs.nextcloud.com/server/stable/user_manual/en/files/access_webdav.html)
- [Standalone rclone WebDAV server: TLS and authentication](https://rclone.org/commands/rclone_serve_webdav/)
- [Git garbage collection and history reachability](https://git-scm.com/docs/git-gc)
