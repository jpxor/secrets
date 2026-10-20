# Backup provider setup

The APK talks directly to the selected provider. No server, client secret, or shared storage account is operated by Secrets. App registrations are needed for Google, Microsoft and Dropbox. They are not bundled with credentials from a developer's personal account. All vault uploads are encrypted before native backup code sees them.

Only one destination is active. Connection inspects the destination before activation. Existing backups belonging to another vault must be restored, never silently overwritten. Manual import disconnects the previous provider and disables the previous biometric binding. Reconnect after import to resume automatic backup. Keep the remote account and passphrase accessible independently of the lost phone.

## Google Drive

1. Create a Google Cloud project, enable Google Drive API and configure OAuth consent.
2. Register an Android OAuth client for `app.secretskeeper.secrets` with the signing certificate SHA-1 of the APK being distributed. Debug and distribution signing identities differ. Use Gradle `signingReport` for fingerprints.
3. Authorize `https://www.googleapis.com/auth/drive.appdata`. Development/testing consent may require listing test users. Complete any provider review required for distribution.
4. The app uses Google Play services AuthorizationClient; it obtains fresh access tokens without a developer server. It requests no master passphrase from Google.

Google Play services must be available. Revoked consent/account changes require reconnecting. Storage quota is the user's Drive quota; a full account cannot receive backups.

## OneDrive personal accounts

1. Register a Microsoft public-client/native application supporting personal Microsoft accounts.
2. Register the mobile custom redirect URI `app.secretskeeper.secrets:/oauth2redirect` and enable public-client authorization as required by Microsoft.
3. Grant delegated `Files.ReadWrite.AppFolder` and `offline_access`. The application writes only its app folder using Microsoft Graph.
4. Supply the public application ID in the setup screen, or compile with `--dart-define=SECRETS_MICROSOFT_CLIENT_ID=...`.

OAuth authorization-code + PKCE runs in the system browser through AppAuth. Refresh tokens are protected using a device-only Keystore key; no client secret is embedded in the app. Work/school tenants are outside v1 scope.

## Dropbox

1. Register a scoped Dropbox API application with **App folder** access.
2. Enable `files.metadata.read`, `files.content.read`, `files.content.write` and register `app.secretskeeper.secrets:/oauth2redirect` as redirect URI.
3. Supply its public app key in setup or compile with `--dart-define=SECRETS_DROPBOX_APP_KEY=...`.
4. Complete any Dropbox production approval needed before distributing to a broader audience.

AppAuth uses authorization code + PKCE and requests offline access. Tokens are stored only in the encrypted device-local configuration. The app-folder API sees paths relative to the application's folder.

## SFTP

Supply host, port (22 default), username, password or private key, optional key passphrase, directory and SHA256 server host-key fingerprint. The directory is created if permissions allow. Use a dedicated directory with write/list/read/delete permissions. All network operations use SSH; there is no shell-command interpolation.

Obtain the fingerprint from the server administrator through a trusted channel. For an administrator with console access, `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256` can show the server key fingerprint. Several host-key algorithms may exist; pin the key actually offered to the client. Unknown or changed keys are rejected. Connection errors can display the offered fingerprint, but that display alone does not verify its authenticity.

## Generic Git

Supply an `https://...` or `ssh://...` repository URL, branch (default `main`), backup subdirectory (default `Secrets`), and credentials. Use a dedicated repository. The selected branch must already exist, or the remote repository must be empty so Secrets can create the branch. HTTPS uses a username/password or host-issued access token; SSH uses a private key or server-supported password and a pinned SHA256 host key. For nonstandard SSH ports use `ssh://user@host:port/path/repo.git`.

This is standard JGit transport, with JSch SSH—not GitHub-specific APIs and not a call to a Git binary on the phone. Pushes never force-update a branch. Remote rejection/conflict preserves remote data and surfaces a retry/error. The active directory retains five snapshots; older commits retain encrypted history. Git servers with interactive browser-only authentication or special transport requirements need appropriate HTTPS tokens/SSH credentials.

HTTPS uses Basic authentication over TLS with a password/token; Kerberos/Negotiate and interactive browser-only Git login are outside v1 scope. Bouncy Castle supplies modern SSH cryptographic algorithms on older Android versions. Release shrinker rules preserve JSch's reflection-loaded implementations. Temporary Git clones disable desktop-only automatic GC and are removed after each operation; server-side repository maintenance remains the server's responsibility.

Persisted clone URLs omit authentication user-info. SSH usernames and credentials are injected in memory; provider configuration remains encrypted. Pack caches are explicitly released with JMX/memory mapping disabled before symlink-safe cleanup. A local HTTPS test verifies rejection of untrusted certificates before credentials are sent.

## Recovery / account changes

On a fresh phone choose **Restore from backup provider**, authorize or enter connection details, then enter the master passphrase. The app authenticates and decrypts the backup before replacing local data. A new biometric binding can then be enabled. Provider credentials are not inside exported vault files, so SFTP/Git connection details and keys must also be available separately.

If an active remote backup changed outside this installation, automatic writes stop rather than guessing. Reconnect to inspect the destination. This application is not a simultaneous multi-device editor.
