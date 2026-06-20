# Testing the widget locally (without a release)

Widget changes are hard to verify in Xcode: the SwiftUI **previews don't render
widgets** on macOS ("This platform does not support previewing widgets"), and a
plain `#Preview` can't force a family because `\.widgetFamily` is read-only. The
reliable loop is to build a Release copy, swap it into `/Applications`, and look
at the real widget — and the **data only shows up if the App Group matches**.

## Why the data shows up (the key detail)

The app writes recent pads into a **team-ID-prefixed App Group container**
(`6L9H6Q8CUF.group.com.adamdangoor.coderpad`, see `WidgetSharedStore`), and the
widget reads them back from it. A locally-built copy only sees that data if it is
signed with the **same Team ID** (`6L9H6Q8CUF`) as the installed app — otherwise
it gets a *different*, empty container and the widget shows the empty state.

Both the project's **Apple Development** and **Developer ID Application**
identities are team `6L9H6Q8CUF`, so a normal local Release build
(`CODE_SIGN_STYLE=Automatic`) shares the container — no notarization needed for
your own Mac.

Confirm the teams match before swapping:

```sh
codesign -dvv <new>/CoderPad.app 2>&1 | grep TeamIdentifier        # 6L9H6Q8CUF
codesign -dvv /Applications/CoderPad.app 2>&1 | grep TeamIdentifier # 6L9H6Q8CUF
```

## Procedure

```sh
# 1. Build Release locally (embeds + signs the widget extension)
xcodebuild -project coderpad.xcodeproj -scheme coderpad \
  -configuration Release -derivedDataPath /tmp/cp-rel \
  build CODE_SIGN_STYLE=Automatic
NEW=/tmp/cp-rel/Build/Products/Release/CoderPad.app

# 2. Quit the running copy and its widget extension
osascript -e 'quit app "CoderPad"' || true
killall CoderPad RecentPadsWidgetExtension 2>/dev/null || true

# 3. Back up and replace the installed app (keeps the App Group container)
cp -R /Applications/CoderPad.app "/Applications/CoderPad backup.app"
rm -rf /Applications/CoderPad.app
cp -R "$NEW" /Applications/CoderPad.app

# 4. Re-register with LaunchServices and launch (repopulates the App Group)
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f /Applications/CoderPad.app
open /Applications/CoderPad.app
```

## Force the widget to re-render

WidgetKit caches the previous render and may keep serving the **old extension
binary**, so after installing:

1. Open **Edit Widgets** / Notification Center.
2. **Remove** the CoderPad widgets, then **re-add** them — this picks up the new
   extension. (`killall chronod` also nudges it.)

## Caveats

- A local build is versioned `1.0 (1)` and **not notarized**. Don't let Sparkle
  "update" it mid-test — it would reinstall the latest published release and undo
  your change. Restore the notarized build from the backup (or reinstall the
  release) when finished.
- This is for **testing only**. Ship real changes through the tagged
  `release.yml` pipeline (see [releasing.md](releasing.md)).
