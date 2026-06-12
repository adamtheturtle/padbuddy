# Releasing

Releases use **semantic version tags** (`vMAJOR.MINOR.PATCH`, e.g. `v1.0.0`) and
the **GitHub Releases** page, with release notes generated automatically from the
git log.

## Cut a release

1. Make sure `main` is green (the CI workflow builds and tests every push).
2. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION` for each upload) in the
   project's build settings if you haven't already (see issue #48).
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

The artifact produced by the workflow is **ad-hoc/unsigned**, which is fine for
testing and archival but not for redistribution. Developer ID signing +
notarization (so the app runs on other Macs without Gatekeeper warnings) requires
a paid Apple Developer account and signing secrets, and is tracked in #29 and
#150. App Store builds are notarized automatically by App Store Connect.
