# Releasing

Releases use **semantic version tags** (`vMAJOR.MINOR.PATCH`, e.g. `v1.0.0`) and
the **GitHub Releases** page, with release notes generated automatically from the
git log.

## Cut a release

1. Make sure `main` is green (the CI workflow builds and tests every push).
2. Bump the version with the helper, which sets `MARKETING_VERSION` and
   `CURRENT_PROJECT_VERSION` across every build configuration at once (so no
   target ships a mismatched version):

   ```sh
   scripts/bump-version.sh 1.3.0        # marketing 1.3.0, build auto-incremented
   scripts/bump-version.sh 1.3.0 47     # pin the build number explicitly
   ```

   Review the diff and commit it. Every App Store upload needs a unique build
   number, so bump at least the build for each one.
3. Tag the release commit with a semver tag and push the tag:

   ```sh
   git tag v1.2.0
   git push origin v1.2.0
   ```

4. The `Release` workflow (`.github/workflows/release.yml`) then runs on the tag:
   it builds the app in Release configuration, zips the `.app`, generates notes,
   and publishes a GitHub Release with the artifact attached.

## Release notes

Notes are produced by `scripts/release-notes.sh`, which lists the non-merge
commit subjects since the previous tag plus a compare link. To preview them
locally before tagging:

```sh
scripts/release-notes.sh            # previous tag → HEAD
scripts/release-notes.sh v1.1.0     # from a specific tag → HEAD
```

Keep commit subjects clear and user-facing — they become the release notes
verbatim.

## Signing & notarization

To redistribute the app directly (outside the Mac App Store) it must be signed
with a **Developer ID Application** certificate and **notarized**, or macOS
Gatekeeper shows an "app is damaged / Apple cannot check it" warning on other
people's Macs.

The `Release` workflow handles this automatically **when the signing secrets
below are configured**: it signs the app, packages it as a notarized, stapled
`.dmg`, and attaches that to the GitHub Release. When the secrets are absent it
falls back to an **ad-hoc/unsigned `.zip`** — fine for testing and archival, not
for redistribution. (App Store builds are notarized automatically by App Store
Connect and are unaffected by this.)

### Required repository secrets

Set these under **Settings → Secrets and variables → Actions**:

| Secret | What it is |
| --- | --- |
| `DEVELOPER_ID_APP_CERT_P12_BASE64` | The Developer ID Application certificate + private key exported as a `.p12`, base64-encoded (`base64 -i cert.p12 \| pbcopy`) |
| `DEVELOPER_ID_APP_CERT_PASSWORD` | The password protecting that `.p12` |
| `ASC_KEY` | The App Store Connect API `.p8` key, base64-encoded (`base64 -i AuthKey_XXXX.p8 \| pbcopy`) |
| `ASC_KEY_ID` | The key's 10-char ID (the `XXXX` in the `.p8` filename) |
| `ASC_ISSUER_ID` | The issuer UUID from App Store Connect → Users and Access → Integrations |

Obtaining the Developer ID Application certificate requires a **paid** Apple
Developer account ($99/yr); the free account cannot issue one. Export it from
Keychain Access (or download from the Developer portal) as a `.p12` including the
private key.

### Signing locally

`scripts/package-and-notarize.sh` runs the same sign, `.dmg`, notarize, staple,
validate pipeline against an already-built `Release` `coderpad.app`. With the
Developer ID identity in your login keychain:

```sh
export SIGNING_IDENTITY="Developer ID Application: Your Name (6L9H6Q8CUF)"
export ASC_KEY="$(base64 -i AuthKey_XXXXXXXXXX.p8)"
export ASC_KEY_ID="XXXXXXXXXX"
export ASC_ISSUER_ID="00000000-0000-0000-0000-000000000000"
scripts/package-and-notarize.sh path/to/coderpad.app coderpad.dmg
```

Hardened Runtime is already enabled for the Release configuration (required for
notarization); the script embeds `PadBuddy/PadBuddy.entitlements` when signing.
