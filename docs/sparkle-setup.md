# Sparkle in-app updates (#28)

The app ships with a **build-safe Sparkle scaffold**: all Sparkle code is behind
`#if canImport(Sparkle)` (`coderpad/SoftwareUpdater.swift`), so the project builds
with or without the dependency. The feature stays dormant until the one-time setup
below is done. Until then there is no "Check for Updates…" menu item and no
background update checks.

## What's already wired

- `SoftwareUpdater` wrapper around `SPUStandardUpdaterController`, started at launch
  (`AppDelegate.applicationDidFinishLaunching`).
- A **Check for Updates…** command in the app menu, just under About.
- `Info.plist`: `SUFeedURL` (points at the appcast attached to the latest GitHub
  Release) and a **placeholder** `SUPublicEDKey`.
- `release.yml` + `scripts/generate-appcast.sh`: when the `SPARKLE_PRIVATE_ED_KEY`
  repo secret is set, each tagged release generates a signed `appcast.xml` and
  attaches it. Inert until that secret exists.

## One-time setup (manual)

1. **Add the package.** Xcode ▸ File ▸ Add Package Dependencies… ▸
   `https://github.com/sparkle-project/Sparkle`, pin "Up to Next Major", add the
   `Sparkle` library to the **coderpad** app target. This flips `canImport(Sparkle)`
   true and activates the scaffold.

2. **Generate EdDSA keys.** Run Sparkle's tool (from the package's artifacts, or
   `Sparkle-x.y.z.tar.xz` ▸ `bin/generate_keys`):

   ```sh
   ./bin/generate_keys                 # creates/stores the private key in the Keychain
   ./bin/generate_keys -p              # prints the PUBLIC key
   ./bin/generate_keys -x private.pem  # exports the PRIVATE key (keep secret!)
   ```

   - Paste the **public** key into `Info.plist` `SUPublicEDKey` (replace
     `REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY`).
   - Add the **private** key's contents as the repo secret `SPARKLE_PRIVATE_ED_KEY`.

3. **Sandbox entitlements (required — the app is sandboxed).** Sparkle's updater
   runs in XPC services that need explicit sandbox permission. Per Sparkle's
   "Sandboxing" guide, add to `coderpad/coderpad.entitlements`:
   - `com.apple.security.temporary-exception.mach-lookup.global-name` →
     `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` (Sparkle's installer XPC) and
     `$(PRODUCT_BUNDLE_IDENTIFIER)-spki` (its progress/launcher), and
   - set `SUEnableInstallerLauncherService` = `YES` in `Info.plist`.

   Follow the current Sparkle docs exactly — the precise keys depend on the Sparkle
   version. Verify the sandboxed app can download and install an update before
   shipping. Re-confirm `scripts/package-and-notarize.sh` still signs the embedded
   Sparkle XPC services (it signs nested code inside-out, so they should be covered,
   but check on the first signed release).

4. **First release.** Tag a `v*` release. With `SPARKLE_PRIVATE_ED_KEY` set, the
   workflow runs `scripts/generate-appcast.sh` and attaches `appcast.xml`.
   **`generate-appcast.sh` is unverified end-to-end** — confirm the appcast's
   enclosure URL, version, and signature on this first run and adjust if needed
   (e.g. the pinned `SPARKLE_VERSION`, or how `generate_appcast` reads the key).

## How updates flow afterwards

Installed copies read `SUFeedURL` →
`…/releases/latest/download/appcast.xml`, verify the new build against
`SUPublicEDKey`, and offer the update. Background checks are scheduled by the
updater; the menu item triggers a manual check.
