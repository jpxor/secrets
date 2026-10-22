# Wallust domain migration

## Cutover on 2026-10-22

The maintainer approved using the existing jpxor/wallust repository for a simple
public placeholder, then explicitly approved making that repository public after
GitHub rejected Pages on the private repository under the current plan.
No new repository was created and no old Wallust history was copied into it.
The previous live site was served from jpxor.github.io and identified Publii as
its generator; wallust-hugo is a separate older project, left unchanged.

| Repository | Live address | Publishing source |
| --- | --- | --- |
| jpxor/wallust | https://www.wallust.com/ | main:/docs |
| jpxor/jpxor.github.io | https://jpxor.github.io/ | main:/docs |
| jpxor/secrets | https://jpxor.github.io/secrets/ | Actions, web/ |
| jpxor/worklog (local time-tracker) | https://jpxor.github.io/worklog/ | Actions, site/ |
| jpxor/parrot | https://jpxor.github.io/parrot/ | master:/ |
| jpxor/Photoloom | https://jpxor.github.io/Photoloom/ | personal:/docs |

GitHub reports HTTPS enforcement on all six sites. Apex wallust.com and www both
respond successfully. No DNS records were changed. Rebuilt the account site after
changing its source to /docs; its live title is now jpxor — Projects.

Wallust commits b2db06b and 720a622 add the placeholder and compatibility links;
GitHub generated its docs/CNAME in 8f5b465. Account-site commit a79f9cd removes the
old root CNAME and adds the neutral project index. Original content remains in
Git history. No publisher webhook was configured on the account repository.
Future external Publii publishers must not restore the account custom domain.

## Compatibility and project updates

Wallust temporarily serves copies of Secrets' public homepage, privacy, support
and stylesheet at the old /secrets/ addresses. Their Git blob hashes were checked
against the already-public Secrets origin/main:web files before publication.
The maintainer confirmed retaining these pages during Google's migration.
They contain no app vault data, provider credentials or private configuration.
Keep them until replacement Google branding is verified and published; then
replace them with explicit redirects to the corresponding new pages.

Old WorkLog, Parrot and Photoloom homepages use HTML refresh/canonical links.
Wallust's 404 page forwards deep links for only the four known project prefixes
to the same path/query/fragment on https://jpxor.github.io. These are browser
redirects, not server-side HTTP 301 responses. Unknown paths remain a 404 page.

Photoloom's Hugo baseURL and generated HTML/XML were updated together in commit e5ed2e1 on
personal to replace hard-coded wallust.com/Photoloom URLs. Its application and
photo processing are unchanged. Parrot has no hard-coded Wallust URLs. WorkLog
uses relative website links; unrelated local edits to its README, site and Pages
workflow were preserved. Repository homepage metadata for Wallust, Secrets and
WorkLog now points to their intended live URLs.

Secrets README and canonical tags now use github.io, with the public Search
Console verification meta tag in the homepage. Its protected main branch requires
checks and a PR; see https://github.com/jpxor/secrets/pull/2.

## Google production status

Project booming-banner-512323-p7 accepted and saved homepage
https://jpxor.github.io/secrets/, privacy policy
https://jpxor.github.io/secrets/privacy.html and authorized domain jpxor.github.io.
The maintainer explicitly approved submitting verification and publishing the
result. Google reported that the homepage was not registered to its owner.
Search Console confirmed homepage ownership using the deployed HTML meta tag on
2026-10-22. Final branding publication remains pending; the UI asks for 24 hours
after ownership verification before retrying.

The Android OAuth client, package, signing certificate, support/developer contacts,
production audience and drive.appdata scope were not changed. No client secret,
new API key, service account or signing material was created. No on-device Drive
round trip was performed for this website migration.

## Validation and rollback

All six site homepages and Secrets privacy/support were fetched over HTTPS with
successful responses. Photoloom deployment completed; 3,827 internal absolute
links/assets map to existing files. A browser check confirmed an old Wallust photo
deep link reaches the corresponding github.io detail page.
Local scripts/check.ps1 passed formatting, static analysis,
16 Flutter tests, native tests, Android lint, tooling checks and the debug APK
build. No application runtime code changed. Public CI for PR #2 passed (Android
checks run 39723843704, 6m 5s), and PR #2 merged in cd2c3d9. Pages deployed the
ownership challenge successfully. Google branding re-verification/publication
remains pending the ownership propagation interval.

To roll back hosting, remove Wallust's custom-domain binding, restore account-site
commit 47350413b7341d13cf051d43b9ba7f8983b7acff and its main:/ source, then reassign
www.wallust.com to the account site. Verify HTTPS and all project paths. Revert
project URL commits/settings as needed. Google's prior URLs can be restored, but
branding verification/publication may need another review. Preserve DNS ownership
records, repositories, Git history and Android identity throughout.
