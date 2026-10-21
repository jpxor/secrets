# Public repository, Pages and Google production setup

Prepared 2026-10-20. This is a preparation record, not evidence of publication.

## Final identities

- Repository: `https://github.com/jpxor/secrets`, default branch `main`.
- Pages homepage: `https://jpxor.github.io/secrets/`.
- Privacy policy: `https://jpxor.github.io/secrets/privacy.html`.
- Recovery/support: `https://jpxor.github.io/secrets/support.html`.
- Public support: `https://github.com/jpxor/secrets/issues`.
- Private vulnerabilities: enable GitHub private vulnerability reporting; root
  SECURITY.md documents a safe fallback until this is enabled.

These are intended URLs until the repository/Pages deployment is verified live.
The maintainer selected the GitHub account and Issues support route. Google still
requires an email for consent support/developer contact: keep the already approved
account-managed contact there, without copying it into public source.

## Repository and Pages

1. Review the prepared content and history review results in PROGRESS.md.
2. Create `jpxor/secrets` without generated README/license/gitignore. Push the
   existing reviewed history with `main` as default; do not rewrite published history.
3. Enable Issues, private vulnerability reporting, dependency alerts and Actions.
   Require passing Android CI for changes to main. Do not provision CI signing keys.
4. Set Settings → Pages → Build and deployment → Source to **GitHub Actions**.
   The Pages workflow uploads only `web/`, never the repository or SDK caches.
5. Run the Pages workflow. Verify homepage, privacy and support return successfully
   over HTTPS, all links resolve and layouts work on phone and desktop.
6. Run Android CI from the pushed source. Record the commit/run and deployed URLs.
   No APK/tag is published by the Pages workflow.

The site uses system fonts and static HTML/CSS, with no analytics, forms or remote
assets. Relative internal links support GitHub project-site paths. The policy
describes provider/hosting metadata and retention instead of promising that third
parties collect nothing.

## Google production worksheet

Use the existing project and public Android identity in config/google-drive.public.json.
Do not create a web client secret, change signing keys, broaden scopes or move backups
to another project. Current Cloud branding has Secrets as name, the previously
approved email contacts, empty homepage/privacy fields, and Testing status.

| Field | Intended value |
| --- | --- |
| App name | Secrets |
| Homepage | https://jpxor.github.io/secrets/ |
| Privacy policy | https://jpxor.github.io/secrets/privacy.html |
| Terms | Leave empty; no separate terms document is prepared |
| Authorized domain candidate | jpxor.github.io |
| Audience | External; transition Testing → In production after public pages/ownership checks |
| Scope | https://www.googleapis.com/auth/drive.appdata only |
| Support/developer email | Preserve the already approved contacts in Cloud Console |

Google identifies the registrable domain using the Public Suffix List and requires
ownership verification for branding domains. Do not claim the GitHub Pages address
has passed this check until Google's actual verification accepts it. Add a Search
Console URL-prefix property for the Pages address with the Cloud project owner/editor
account. Use the HTML verification file or meta tag Google supplies; commit only that
public verification token, never credentials. If Google requires a different domain
ownership method, record the exact result and obtain a maintainer-selected custom
domain rather than inventing one or purchasing it automatically.

A Search Console URL-prefix property was added and its public HTML meta challenge
is prepared in web/index.html. Ownership has **not** been verified: the page must
first be published. Keep the tag after successful verification. This URL-prefix
challenge does not itself prove that OAuth's authorized-domain check will accept
the project-site address. config/google-production.public.json records planned
values separately from the existing working Android identity.

After Pages and ownership are live, save branding links and the accepted authorized
domain. Follow Verification Center's requirements, verify and publish branding where
required, and publish the audience. Publishing the audience and publishing branding
are separate steps. Do not assert approval from a saved draft.

Test with an account absent from the test-user list: authorization, encrypted upload,
fresh-install recovery, restart/background authorization and revocation/reauthorization.
The owner must enter account credentials and a synthetic vault passphrase privately.
Until these checks pass, keep the site/release notes explicit that general-user Drive
availability and fresh-device recovery are not verified.

## Licenses and distribution

The settings license button is removed. THIRD_PARTY_LICENSES.md is the consolidated
component/license inventory plus full collected notices. Regenerate with
`scripts/update-licenses.ps1` after dependency changes. Flutter's generated NOTICES.Z,
the app LICENSE and native notices remain in the APK. Attach the consolidated document
alongside every release APK; a source-repository mapping alone is insufficient to
replace upstream redistribution notices. Review Google SDK terms separately from the
Apache-2.0 project license. Include corresponding-source links for OpenJDK-derived
desugaring code and any other source-availability obligations.

## References checked during preparation

- [Google brand verification and domains](https://developers.google.com/identity/protocols/oauth2/production-readiness/brand-verification)
- [Drive application data and non-sensitive scope](https://developers.google.com/workspace/drive/api/guides/appdata)
- [Apache-2.0 redistribution requirements](https://www.apache.org/licenses/LICENSE-2.0.html)

Device/recovery, signing-key backup, advisory review and beta/stable gates remain in
RELEASE_PLAN.md. Website/source preparation does not complete those gates.
