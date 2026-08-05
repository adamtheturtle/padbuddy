# visionOS UI smoke

The opt-in smoke covers a narrow first-run welcome window, the default seeded
three-column window, and Settings → Accounts. Each state is attached to the
result bundle as a retained screenshot.

Run it from the Actions tab with **CI → Run workflow**. The
`visionOS UI smoke` job discovers an available Apple Vision Pro simulator and
uploads `VisionSmoke.xcresult`.

To run the same targeted suite locally, substitute an available simulator name:

```sh
scripts/run-xcodebuild.sh VisionSmoke.log test \
  -quiet \
  -showBuildTimingSummary \
  -project coderpad.xcodeproj \
  -scheme coderpad \
  -testPlan VisionSmoke \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro' \
  -resultBundlePath VisionSmoke.xcresult \
  -only-testing:coderpadUITests/CoderpadVisionUITests
```
