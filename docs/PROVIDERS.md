# Backup provider setup

The APK talks directly to the selected provider. No server, client secret, or shared storage account is operated by Secrets. Google Drive uses a maintainer-owned Android OAuth registration. SFTP uses the user's server credentials. No developer account credentials are bundled. All vault uploads are encrypted before native backup code sees them.

Only one destination is active. Connection inspects the destination before activation. Existing backups belonging to another vault must be restored, never silently overwritten. Manual import disconnects the previous provider and disables the previous biometric binding. Reconnect after import to resume automatic backup. Keep the remote account and passphrase accessible independently of the lost phone.

## Google Drive

The maintainer registers each distributed signing identity once; users only choose their Google account and grant app-data access. Android AuthorizationClient identifies the app using its package and signing certificate, so no OAuth client secret, service-account key, API key, client-ID entry field or google-services.json is required in this implementation. The Android OAuth registration must exist in Google Cloud even though no client ID is supplied in code.

Current locally distributed APK registration values (public):

- Registration metadata: `config/google-drive.public.json`. Created in the dedicated Secrets project; Drive API is enabled. This file contains no secrets and is documentation, not runtime configuration: Play services matches the package and signer to the registered Android client.
- Application name: `Secrets`.
- Android package: `app.secretskeeper.secrets`.
- Signing certificate SHA-1: `B3:00:7C:64:75:1D:B0:80:6C:6D:4D:A1:F1:E1:02:9C:CF:9F:92:4B`.
- Scope: `https://www.googleapis.com/auth/drive.appdata` (non-sensitive app-data access).
- Audience: External, initially Testing with explicitly added test users. Public releases require the appropriate production/branding setup.
- The owner account is configured as a test user. Additional testers must be added in Google Auth Platform > Audience. Personal email addresses/test-user lists are managed in Google Cloud and are not committed here. Support and developer contact addresses were explicitly approved by the owner and configured in Google Cloud.
- Do not create a web client secret or service account. Registration administration and APK private signing keys stay outside the source repository. Register a separate Android client for any other signing certificate; do not rotate the installed app's signing key just to configure OAuth.

Authorize first, then inspect existing backups, activate only after conflict checks, and verify an upload. A full Google account can authorize successfully but cannot accept new backups. The app distinguishes authorization cancellation, developer configuration/network failures and Drive's `storageQuotaExceeded` upload response without displaying provider response text.

1. Create a Google Cloud project, enable Google Drive API and configure OAuth consent.
2. Register an Android OAuth client for `app.secretskeeper.secrets` with the signing certificate SHA-1 of the APK being distributed. Debug and distribution signing identities differ. Use Gradle `signingReport` for fingerprints.
3. Authorize `https://www.googleapis.com/auth/drive.appdata`. Development/testing consent may require listing test users. Complete any provider review required for distribution.
4. The app uses Google Play services AuthorizationClient; it obtains fresh access tokens without a developer server. It requests no master passphrase from Google.

Google Play services must be available. Revoked consent/account changes require reconnecting. Storage quota is the user's Drive quota; a full account cannot receive backups.

## SFTP

Supply host, port (22 default), username, password or private key, optional key passphrase and directory. Connect to see a trust dialog displaying the host/port and SHA256 server fingerprint; no fingerprint typing is required. Password authentication does not require a private key or key passphrase. The directory is created if permissions allow. Use a dedicated directory with write/list/read/delete permissions. All network operations use SSH; there is no shell-command interpolation.

Compare the displayed fingerprint with the server administrator's value through a trusted channel, then choose **Trust and connect** or cancel. For an administrator with console access, `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256` can show the server key fingerprint. Several host-key algorithms may exist; pin the key actually offered to the client. A displayed fingerprint alone does not establish authenticity.

Unknown keys are rejected before authentication until explicitly approved; the app reconnects with the approved key pinned and saves it when the backup destination is activated. Existing saved trust is reused only for the same host and port. A different key is rejected, including by background jobs. Reconnect in Settings to review the old/new fingerprints and explicitly choose **Trust new key** only after verifying the change. Cancellation leaves the existing provider unchanged; a server that changes keys between the prompt and reconnection is rejected again.

## Recovery / account changes

On a fresh phone choose **Restore from backup provider**, authorize or enter connection details, then enter the master passphrase. The app authenticates and decrypts the backup before replacing local data. A new biometric binding can then be enabled. Provider credentials are not inside exported vault files, so SFTP connection details and keys must also be available separately.

If an active remote backup changed outside this installation, automatic writes stop rather than guessing. Reconnect to inspect the destination. This application is not a simultaneous multi-device editor.

## Removed providers

OneDrive, Dropbox and Git are not available in this release. Their source remains in Git history. Upgrading preserves the local encrypted vault and remote backups; it never silently switches destinations. A legacy provider configuration produces a clear unsupported-provider error. Export locally and configure Google Drive or SFTP. Previously saved .secrets envelopes remain compatible with manual import; remote files and Git history are not deleted by this change. Never rely on a removed destination for ongoing backup.
