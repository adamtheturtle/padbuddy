# Cutting a release

Releases are fully automated: **tag a commit and push the tag.** A push of a `v*`
tag triggers `.github/workflows/release.yml`, which builds the Release configuration,
signs it with Developer ID, notarizes + staples a `.dmg`, generates the signed Sparkle
`appcast.xml`, and publishes both to the **public** artifacts repo
[`coderpad-macos-releases`](https://github.com/adamtheturtle/coderpad-macos-releases)
(source stays private — see [sparkle-setup.md](sparkle-setup.md)). Installed copies then
auto-update to it.

## Steps

```sh
# 1. Up-to-date, green main with the commit you want to ship as HEAD.
git checkout main && git pull

# 2. (Optional) add a "## v0.1.6" section to CHANGELOG.md and commit it.

# 3. Tag (annotated) and push the tag — the push is what triggers the release.
git tag -a v0.1.6 -m "v0.1.6"
git push origin v0.1.6

# 4. Watch it.
gh run watch "$(gh run list --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
```

That's the whole process — no per-release setup. The signing certificate, notarization
credentials, the Sparkle EdDSA key, and the `RELEASES_REPO_TOKEN` (which lets the
workflow publish cross-repo) are already configured as repo secrets.

## Versioning

- **Marketing version** comes from the tag: `v0.1.6` → `MARKETING_VERSION = 0.1.6`.
- **Build number** is the git commit count (`git rev-list --count HEAD`), so it rises
  automatically — no `Info.plist` edits. Sparkle compares this (`CFBundleVersion`), so a
  new release must sit on **at least one commit more** than the previous one (normal
  forward progress on `main` satisfies this).
- **Never reuse or move a tag** — one tag is one release.

## Before you tag

- **`main` must be green and clean.** The tag builds whatever commit it points at, so
  stray debug code (e.g. `print` statements) ships. The Release build runs under
  warnings-as-errors with a 250 ms type-check-timing budget, so a body that's too slow
  to type-check fails *only* here, not in the normal CI build — keep heavy SwiftUI
  bodies split.
- **Accessibility Inspector must be fresh.** Run the critical-screen accessibility
  audit, resolve P0/P1 findings, and update `docs/cross-cutting-quality-audit.md`.
  The release workflows run `scripts/check-accessibility-release-gate.sh` and fail
  if that audit doc was not updated since the previous release tag.
- If `main` is briefly broken, tag a known-good commit instead (`git tag -a v0.1.6 -m … <sha>`).

## Verify a release

- The release on `coderpad-macos-releases` is marked **Latest** (not pre-release) with
  both `coderpad-<tag>.dmg` and `appcast.xml` attached.
- The feed resolves over plain HTTPS, **unauthenticated**:
  `curl -sSL https://github.com/adamtheturtle/coderpad-macos-releases/releases/latest/download/appcast.xml`
  should return the appcast with the right `sparkle:version`.
- **The DMG actually launches.** Notarization does *not* catch every launch problem
  (e.g. provisioning-profile-required entitlements, unexpanded entitlement variables),
  so download it and confirm it opens on a real Mac — `open` returns 0, no "can't be
  opened". This is the step that caught the v0.1.x launch bug.

## Fixing a bad release

A published release can't be un-shipped from installed copies, but you can supersede it:
just cut a **higher** version with the fix (the appcast's Latest pointer updates, and
Sparkle offers the newer build). Delete the bad release from `coderpad-macos-releases` so
no one downloads it.

## Where the logic lives

- `.github/workflows/release.yml` — the pipeline (build → sign → notarize → appcast → publish).
- `scripts/package-and-notarize.sh` — Developer-ID signing (incl. nested Sparkle code),
  entitlement-variable expansion, DMG packaging, notarization + stapling.
- `scripts/generate-appcast.sh` — the signed Sparkle appcast (enclosure URLs point at
  the public repo via `RELEASES_REPOSITORY`).
- One-time setup and the public-repo rationale: [sparkle-setup.md](sparkle-setup.md).
