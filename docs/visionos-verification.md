# visionOS UI verification

The spatial smoke suite is opt-in because UI automation needs an uncontended, booted Vision Pro simulator:

```sh
xcodebuild test \
  -project PadBuddy.xcodeproj \
  -scheme PadBuddy \
  -testPlan VisionUI \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro' \
  -only-testing:PadBuddyUITests/CoderpadVisionUITests
```

The suite checks both the account-free welcome card and the seeded three-column Pads window.
For a release candidate, also resize the seeded window through wide, medium, and narrow widths and confirm the sidebar, then detail column, collapse without clipped rows or controls.

The suite also retains large-text captures at 640×520, 1040×720, and 1440×900 in light and dark app appearances.
App appearance is distinct from the surrounding spatial environment.
Before closing #3323, repeat the release-candidate screens over bright and dark spatial backgrounds, enable the system Reduce Transparency setting, and complete physical-device verification.
Simulator captures and an appearance override alone do not establish those outcomes.

## Local verification on 29 October 2026

Xcode 27.1 with the visionOS 27.0 simulator (24M362) passed the seeded navigation, pad overview, question Description, and Settings account-editor flow.
The larger-text matrix passed in both app appearances at all three requested window sizes; the suite checks the actual window bounds rather than assuming a size argument took effect.
The interaction run passed all five tests and retained results in `vision-full-interactions-20261029.xcresult`.
A second full suite passed with a hittable Language filter check at each size.
Its `XCUIScreen.main` captures were 1×1 images on this headless runtime and are not visual evidence.
The smoke helper retains window screenshots and rejects empty images.
The focused `vision-capture-dimensions-20261029.xcresult` check passed with a nonempty retained welcome capture.
Window-only XCTest captures can also be cropped, so compare them with the runtime's full spatial renderer when judging layout:

```sh
xcrun simctl io "<booted-simulator-UDID>" screenshot /tmp/padbuddy-vision-spatial.png
```

A separate full spatial capture of the seeded narrow, larger-text window showed its list and filters fitting in the default bright room.

This run found and repaired decorative glass layers intercepting content taps, a rail accessibility label hiding its individual controls, and Settings content being sized independently of its navigation container.
No physical Vision Pro was connected, and this Xcode installation has no Simulator GUI for manual environment controls.
Physical-device and system accessibility/environment verification remain release requirements.
