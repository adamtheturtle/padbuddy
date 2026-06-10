# CI / CD overview

This project uses **two** CI systems, split by job:

| System | Trigger | Job | Config lives in |
|---|---|---|---|
| **GitHub Actions** | Every PR + push to `main` | Build & unit/UI test | `.github/workflows/ci.yml` (in repo) |
| **Xcode Cloud** | Release tags (`v*`) | Build, sign, archive → TestFlight / App Store | App Store Connect UI + `ci_scripts/` (in repo) |

The idea: GitHub Actions gives fast, free-on-the-margin feedback on every change;
Xcode Cloud handles the signing-and-distribution work that is painful to do
anywhere else. Don't duplicate build-and-test in both.

---

## Enabling Xcode Cloud (one-time, done by a human in Xcode / ASC)

Most of Xcode Cloud is configured outside the repo and needs your Apple
Developer account. Steps:

1. **Apple Developer Program membership** ($99/yr). Required before anything
   can be signed or uploaded.

2. **Create the app record in App Store Connect**
   - App Store Connect → Apps → **+** → New App.
   - Platform: macOS. Set the bundle ID (must match the `coderpad` target's
     `PRODUCT_BUNDLE_IDENTIFIER`). Register the bundle ID under
     Certificates, Identifiers & Profiles first if it doesn't exist.

3. **Share the `coderpad` scheme** ⚠️ required, not yet done
   - The scheme is currently *not* shared (it lives in `xcuserdata`, which is
     gitignored, so it isn't in the repo). GitHub Actions works anyway because
     `xcodebuild` autocreates a scheme on a fresh clone, but **Xcode Cloud
     needs a shared scheme committed to the repo.**
   - In Xcode: **Product → Scheme → Manage Schemes…** → tick **Shared** next to
     `coderpad`, then commit the new file at
     `coderpad.xcodeproj/xcshareddata/xcschemes/coderpad.xcscheme`.

4. **Create the Xcode Cloud workflow** (in Xcode)
   - Open the project → **Report navigator** (⌘9) → **Cloud** tab, or menu
     **Integrate → Create Workflow**.
   - Grant Xcode access to the GitHub repo when prompted.
   - **Scheme:** `coderpad` (the shared scheme from step 3).

5. **Configure the workflow**
   - **Start condition:** Tag changes matching `v*` (so a `git tag v1.0.0 &&
     git push --tags` cuts a release). Avoid "every branch push" — that
     overlaps with GitHub Actions and burns compute hours.
   - **Actions:**
     - *Archive* → Distribution: **TestFlight (Internal Testing Only)** to
       start. Promote to External / App Store when ready.
   - **Post-actions (optional):** notify via Slack/email.

6. **Signing** is automatic. Xcode Cloud manages certificates and provisioning
   profiles for you — this is the main reason to use it over GitHub Actions.
   No certs or secrets to store.

---

## `ci_scripts/`

Xcode Cloud automatically runs these if present (must live next to the
`.xcodeproj`, which is the repo root here). They must be executable (`chmod +x`).

- `ci_post_clone.sh` — runs right after clone, before dependency resolution.
  Most common hook. Currently a no-op (project has no external deps or codegen).
- `ci_pre_xcodebuild.sh` — runs before each xcodebuild action. Placeholder.
- `ci_post_xcodebuild.sh` — (not present) add if you need to process build
  output, e.g. upload dSYMs to a crash reporter.

Useful env vars inside these scripts: `$CI_PRIMARY_REPOSITORY_PATH`,
`$CI_BUILD_NUMBER`, `$CI_WORKFLOW`, `$CI_XCODEBUILD_ACTION`. Full list:
https://developer.apple.com/documentation/xcode/environment-variable-reference

---

## GitHub Actions notes

See `.github/workflows/ci.yml`. It:
- Runs on PRs and pushes to `main`.
- Cancels superseded runs for the same ref (`concurrency`) — macOS runners
  bill at 10× minutes, so not paying for stale builds matters.
- Caches DerivedData between runs to speed up incremental builds.
- Builds and tests the `coderpad` scheme with signing disabled (no certs on
  the runner — distribution is Xcode Cloud's job, not this one).
