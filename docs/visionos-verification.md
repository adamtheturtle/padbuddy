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
The subsequent `vision-full-spatial-captures-20261029.xcresult` run also passed all five tests, with full spatial screenshots and a hittable Language filter check at each size.
The smoke helper captures the full spatial screen.
On this runtime, window-only XCTest captures were cropped even when a full spatial capture showed the window fitting correctly.

This run found and repaired decorative glass layers intercepting content taps, a rail accessibility label hiding its individual controls, and Settings content being sized independently of its navigation container.
No physical Vision Pro was connected, and this Xcode installation has no Simulator GUI for manual environment controls.
Physical-device and system accessibility/environment verification remain release requirements.
