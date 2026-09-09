# visionOS UI verification

The spatial smoke suite is opt-in because UI automation needs an uncontended, booted Vision Pro simulator:

```sh
xcodebuild test \
  -project coderpad.xcodeproj \
  -scheme coderpad \
  -testPlan VisionUI \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro' \
  -only-testing:coderpadUITests/CoderpadVisionUITests
```

The suite checks both the account-free welcome card and the seeded three-column Pads window.
For a release candidate, also resize the seeded window through wide, medium, and narrow widths and confirm the sidebar, then detail column, collapse without clipped rows or controls.
