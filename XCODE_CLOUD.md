# CI / CD overview

This project uses **two** CI systems, split by job:

| System | Trigger | Job | Config lives in |
|---|---|---|---|
| **GitHub Actions** | PRs/pushes: static gates; schedule/dispatch: builds and tests | Lint, policy checks, periodic platform validation | `.github/workflows/ci.yml` (in repo) |
| **Xcode Cloud** | Release tags (`v*`) | Build, sign, archive → TestFlight / App Store | App Store Connect UI + `ci_scripts/` (in repo) |

The idea: GitHub Actions gives fast static feedback on every change and runs compiled-target validation on its scheduled/manual paths.
Xcode Cloud handles the signing-and-distribution work that is painful to do anywhere else.

Local builds and tests are pinned to the stable Xcode version in `.xcode-version` (currently 27.0).
Before invoking a local build directly, run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  scripts/check-xcode-version.sh
```

---

## Enabling Xcode Cloud (one-time, done by a human in Xcode / ASC)

Most of Xcode Cloud is configured outside the repo and needs your Apple Developer account.
Steps:

1. **Apple Developer Program membership** ($99/yr).
   Required before anything can be signed or uploaded.

2. **Create the app records in App Store Connect**
   - App Store Connect → Apps → **+** → New App.
   - Add both **macOS** and **iOS** platforms to the app.
     Set the bundle ID (it must match the `PadBuddy-AppStore` target's `PRODUCT_BUNDLE_IDENTIFIER`, currently `com.adamdangoor.padbuddy` — shared with the `PadBuddy` Developer ID target).
     Register the bundle ID under Certificates, Identifiers & Profiles first if it doesn't exist.
   - The iOS platform covers both iPhone and iPad.
     Supply the platform-specific copy under `app-store/submission/<locale>/ios/` rather than the Mac copy.

3. **Use the shared `PadBuddy-AppStore` scheme** ✅ already shared
   - Mac App Store builds go through the dedicated **`PadBuddy-AppStore`** target, *not* `PadBuddy`.
     The `PadBuddy` target links Sparkle (for direct Developer ID auto-updates), which the App Store rejects; `PadBuddy-AppStore` is the Sparkle-free target whose archive ASC will accept.
   - Both `PadBuddy-AppStore.xcscheme` and `PadBuddy.xcscheme` are already shared and committed under `PadBuddy.xcodeproj/xcshareddata/xcschemes/`, so Xcode Cloud can see them.

4. **Create the Xcode Cloud workflows** (in Xcode)
   - Open the project → **Report navigator** (⌘9) → **Cloud** tab, or menu **Integrate → Create Workflow**.
   - Grant Xcode access to the GitHub repo when prompted.
   - **Scheme:** `PadBuddy-AppStore` (the Sparkle-free Mac App Store target).
     Do **not** pick `PadBuddy` — that archives the Sparkle build and will fail App Store review.

5. **Configure the workflows**
   - **Start condition:** Tag changes matching `v*` (so a `git tag v1.0.0 && git push --tags` cuts a release).
     Avoid "every branch push" — that overlaps with GitHub Actions and burns compute hours.
   - Create one archive action for **macOS** and one for **iOS**.
     Both use the `PadBuddy-AppStore` scheme and `AppStoreRelease` configuration.
     Keeping distinct platform actions makes a failed mobile archive visible instead of silently shipping only the Mac product.
   - Set each archive's distribution to **TestFlight (Internal Testing Only)** to start.
     Promote to External / App Store when ready.
   - **Post-actions (optional):** notify via Slack/email.
   - Add a secret environment variable named **`BUDDY_KIT_TOKEN`** containing a fine-grained GitHub token with read-only Contents access to the private `adamtheturtle/buddy-kit` repository.
     The post-clone hook verifies access before Xcode resolves packages.

6. **Signing** is automatic.
   Xcode Cloud manages certificates and provisioning profiles for you — this is the main reason to use it over GitHub Actions.
   No certs or secrets to store.

---

## `ci_scripts/`

Xcode Cloud automatically runs these if present (must live next to the `.xcodeproj`, which is the repo root here).
They must be executable (`chmod +x`).

- `ci_post_clone.sh` — runs right after clone, before dependency resolution.
  Configures and verifies authenticated SwiftPM access to the private `buddy-kit` dependency using the secret `BUDDY_KIT_TOKEN`.
- `ci_pre_xcodebuild.sh` — runs before each xcodebuild action.
  It rejects an explicitly wrong archive scheme when Xcode Cloud exposes the scheme variable.
- `ci_post_xcodebuild.sh` — verifies that App Store archive intermediates have the expected bundle ID, omit Sparkle, and retain Hardened Runtime.
  Xcode Cloud applies managed distribution signing to the exported product rather than the archive intermediate, so successful App Store export remains the repository's provisioning validation; expired membership, certificates, or profiles fail that export before this script runs.

Useful env vars inside these scripts: `$CI_PRIMARY_REPOSITORY_PATH`, `$CI_BUILD_NUMBER`, `$CI_WORKFLOW`, `$CI_XCODEBUILD_ACTION`.
Full list: https://developer.apple.com/documentation/xcode/environment-variable-reference

---

## GitHub Actions notes

See `.github/workflows/ci.yml`.
It:

- Runs formatting, localization, entitlement, workflow, and shell gates on PRs and pushes to `main`.
- Restricts the macOS/iOS build and test jobs to scheduled or manually dispatched runs; a normal PR currently has no compiled-target signal.
- Cancels superseded runs for the same ref (`concurrency`) — macOS runners bill at 10× minutes, so not paying for stale builds matters.
- Caches DerivedData between runs to speed up incremental builds.
- On scheduled/manual runs, builds and tests the `PadBuddy` scheme with signing disabled (distribution is Xcode Cloud's job).
