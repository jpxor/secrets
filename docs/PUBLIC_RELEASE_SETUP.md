# Public repository, Pages and Google production setup

Published 2026-10-20 with maintainer approval. Application release acceptance remains
separate from publishing source, the website and Google account configuration.

## Live identities

- Repository: https://github.com/jpxor/secrets, default branch `main`.
- Git remote: `git@github.com:jpxor/secrets.git`; use the maintainer's existing SSH identity.
- Homepage: https://jpxor.github.io/secrets/.
- Privacy policy: https://jpxor.github.io/secrets/privacy.html.
- Recovery/support: https://jpxor.github.io/secrets/support.html.
- Public support: https://github.com/jpxor/secrets/issues.
- Private vulnerability reports: https://github.com/jpxor/secrets/security/advisories/new.

On 2026-10-22, Wallust moved to its existing `jpxor/wallust` repository, freeing
the account site and project sites to use `jpxor.github.io`. Secrets remains in
its own repository and Pages deployment. See DOMAIN_MIGRATION.md for cutover
evidence, Google branding status and compatibility URLs.

## Repository and Pages operations

The reviewed existing source history was pushed through SSH; no credentials, SDK
caches, signing keys or vault files were published. Issues/Actions are available.
Private vulnerability reporting and the dependency graph/Dependabot alerts are enabled.
Secret protection and push protection were already enabled and remain enabled.

Settings → Pages uses **GitHub Actions**, with HTTPS enforced. The workflow uploads
only `web/`, never the repository or SDK caches. First successful deployment:
https://github.com/jpxor/secrets/actions/runs/39531305230 (source `a9288b0`).
Homepage, privacy and support were read in the browser over HTTPS. Later deployments
track the exact source commit in Actions. No signed APK, release tag or stable release
was published by these operations.

The site uses system fonts and static HTML/CSS, with no analytics, forms or remote
assets. Relative links support the `/secrets/` project path. Changes to web/ redeploy
through the Pages workflow. Keep privacy/support URLs working before editing consent
branding. Follow the required Android checks when changing the application.

## Google production configuration

Existing project and Android registration are recorded in config/google-drive.public.json.
Public production metadata is in config/google-production.public.json. No web client
secret, new signing key, API key or service account was created. Existing backups
remain associated with the same app/project identity.

| Field | Current configuration |
| --- | --- |
| App name | Secrets |
| Homepage | https://jpxor.github.io/secrets/ |
| Privacy policy | https://jpxor.github.io/secrets/privacy.html |
| Terms | Empty; no separate terms document |
| Authorized domain | jpxor.github.io |
| Audience | External / In production |
| Scope | https://www.googleapis.com/auth/drive.appdata only |
| Branding | New URLs saved; homepage ownership verified; branding re-verification/publication pending |
| Support/developer email | Previously approved account-managed contacts, retained in Cloud only |

The previous wallust.com branding was verified and published on 2026-10-20.
On 2026-10-22 Google accepted the github.io URLs and authorized domain, but
re-verification reported that the new homepage was not registered to the owner.
The deployed HTML meta challenge verified homepage ownership in Search Console
on 2026-10-22. After Google's stated 24-hour propagation interval, re-verify and
publish branding. Do not describe saved draft URLs as published branding.
Verification Center states that data-access verification is not required because
no sensitive or restricted scopes are requested. These are observed Console results,
not a claim that the app passed an independent security review or recovery acceptance.
Google still requires an email for consent support/developer contact; Issues is the
public website support route and cannot replace that account field.

For branding changes, save the changes, repeat the verification required by Google,
and publish the verified branding. A saved draft is not a published result. Keep the
registered package/signing fingerprint and appdata-only scope. Do not change identity
or broaden scopes to work around authorization failures.

## Remaining release validation

The maintainer confirmed successful manual and Google Drive backup/restore round
trips on 2026-10-20. That acceptance task is complete. The report did not specify
whether a fresh independent installation or an account outside the test-user list
was used; those particular conditions remain unclaimed.

Test with a Google account absent from the former test-user list: authorization,
encrypted upload, fresh-install recovery, restart/background authorization and
revocation/reauthorization. The tester enters credentials and a synthetic vault
passphrase privately. No non-test-account or fresh-device result is claimed yet.

Keep the site and release notes explicit about this limitation. Recovery/device,
signing-key backup and beta/stable gates remain in RELEASE_PLAN.md. The latest
signed APK stays local until the separate distribution/acceptance decision.

## Licenses and distribution

The settings license button is removed. THIRD_PARTY_LICENSES.md is the consolidated
component/license inventory plus full collected notices. Regenerate with
`scripts/update-licenses.ps1` after dependency changes. Flutter's generated NOTICES.Z,
the app LICENSE and native notices remain in the APK. Attach the consolidated document
alongside every release APK; a source-repository mapping alone does not replace
upstream redistribution notices. Review Google SDK terms separately from the
Apache-2.0 project license. Preserve corresponding-source links where required.

## Primary references

- [Google branding verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/brand-verification)
- [Drive application data and non-sensitive scope](https://developers.google.com/workspace/drive/api/guides/appdata)
- [GitHub inherited project-site domains](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/about-custom-domains-and-github-pages)
- [Apache-2.0 redistribution](https://www.apache.org/licenses/LICENSE-2.0.html)
