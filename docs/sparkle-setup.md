# Sparkle in-app updates (#28)

> Cutting a release day-to-day is just `git tag` + `git push` — see
> [releasing.md](releasing.md). This file covers the one-time setup and the
> public-repo architecture behind it.

The app ships with a **build-safe Sparkle scaffold**: all Sparkle code is behind
`#if canImport(Sparkle)` (`coderpad/SoftwareUpdater.swift`), so the project builds
with or without the dependency. The feature stays dormant until the one-time setup
below is done. Until then there is no "Check for Updates…" menu item and no
background update checks.

## What's already wired

- `SoftwareUpdater` wrapper around `SPUStandardUpdaterController`, started at launch
  (`AppDelegate.applicationDidFinishLaunching`).
- A **Check for Updates…** command in the app menu, just under About.
- `Info.plist`: `SUFeedURL` points at the appcast on the latest release of the
  **public artifacts repo** `adamtheturtle/coderpad-macos-releases` (see below), and
  `SUPublicEDKey` holds the real EdDSA public key.
- `release.yml` + `scripts/generate-appcast.sh`: each tagged release builds, signs,
  notarizes, generates a signed `appcast.xml`, and publishes the DMG + appcast to the
  public releases repo.
- `scripts/package-and-notarize.sh` re-signs Sparkle's nested code (the
  `XPCServices/*.xpc`, `Updater.app`, and the `Autoupdate` helper) with Developer ID
  - Hardened Runtime + a secure timestamp — **verified** by the notarized v0.1.0 /
  v0.1.1 releases.

## Public releases repo (source stays private)

The source repo is private, but Sparkle fetches the appcast + DMG **unauthenticated**,
and a private repo's release assets 404 without a token. So distribution artifacts
live in a separate **public** repo, `adamtheturtle/coderpad-macos-releases` (built
DMGs + appcast only — no source). `SUFeedURL` and the appcast enclosure URLs point
there.

**The one token you must add:** the release workflow runs in the private repo, whose
default `GITHUB_TOKEN` can't write to another repo. Create a PAT with
**contents:write** on `coderpad-macos-releases` and add it to the **private** repo as
the secret **`RELEASES_REPO_TOKEN`** (a fine-grained PAT scoped to just that repo is
ideal). Until it's set, `release.yml` falls back to publishing in the private repo and
logs a warning — the public feed won't update.

## One-time setup (complete)

All four steps below are **done** — they're recorded here as the current state and
for reference (e.g. how to rotate keys), not as pending work.

1. **Package added.** The `Sparkle` library (sparkle-project/Sparkle, "Up to Next
   Major") is on the **coderpad** app target, committed to the project file +
   `Package.resolved`. `canImport(Sparkle)` is therefore true and the scaffold is
   active.

2. **EdDSA keys generated.** The keypair was created with Sparkle's `generate_keys`;
   the private key lives in the login Keychain and as the repo secret
   `SPARKLE_PRIVATE_ED_KEY`, and the public key is in `Info.plist` `SUPublicEDKey`
   (`GM4rpkCx9FMbd+Sk64pU6v6659APlNWYLMKzGU3OIyU=` — not the old placeholder).

   To **rotate** the keys, re-run Sparkle's tool (from the package's artifacts, or
   `Sparkle-x.y.z.tar.xz` ▸ `bin/generate_keys`), then update `SUPublicEDKey` and the
   `SPARKLE_PRIVATE_ED_KEY` secret:

   ```sh
   ./bin/generate_keys                 # creates/stores the private key in the Keychain
   ./bin/generate_keys -p              # prints the PUBLIC key
   ./bin/generate_keys -x private.pem  # exports the PRIVATE key (keep secret!)
   ```

3. **Sandbox entitlements — already wired.** Because the app is sandboxed,
   `PadBuddy/PadBuddy.entitlements` grants the mach-lookup temporary-exceptions
   `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` (Sparkle's installer XPC) and `-spki` (its
   launcher), and `Info.plist` sets `SUEnableInstallerLauncherService` = `YES`. The
   Downloader service (`-spkd`) is intentionally omitted — the app already holds
   `com.apple.security.network.client`, which Sparkle prefers. The packaging script's
   re-signing of the nested Sparkle XPC services / `Updater.app` / `Autoupdate` is
   **confirmed** (the v0.1.0 / v0.1.1 DMGs notarized cleanly).

4. **Releases are wired and verified.** `generate-appcast.sh` + `release.yml` produce
   a valid signed appcast and publish it; the public feed at
   `…/coderpad-macos-releases/releases/latest/download/appcast.xml` resolves over
   plain HTTPS with a correct `sparkle:version`/enclosure. The remaining check is
   purely on-device: install one version, cut a higher one, and confirm the installed
   copy detects → downloads → installs it. (Both the build's baked-in `SUFeedURL` and
   the published artifacts must point at the public repo, which they now do.)

## How updates flow afterwards

Installed copies read `SUFeedURL` →
`…/coderpad-macos-releases/releases/latest/download/appcast.xml`, verify the new build
against `SUPublicEDKey`, and offer the update. Background checks are scheduled by the
updater; the menu item triggers a manual check.
