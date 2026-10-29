# First account performance budget

The Performance test plan includes `CoderpadAccountBrowserUITests/testFirstRunLoads100PadsWithinBudget`.
It starts without accounts, adds the demo account through Settings, and requires the complete 100-pad list to populate within 10 seconds of validating the account.
The test records the account-to-list path, including list construction and publication of all 100 rows in the main window.
Elapsed time is retained as an xcresult attachment.

Use the isolated UI-test bundle identifier so the runner cannot reuse or terminate a personal app:

```sh
xcodebuild test -project PadBuddy.xcodeproj -scheme PadBuddy -testPlan Performance \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PadBuddyUITests/CoderpadAccountBrowserUITests/testFirstRunLoads100PadsWithinBudget \
  PADBUDDY_TEST_BUNDLE_SUFFIX=.uitesting
```

The explicit `-uiTesting100Pads` launch fixture is available only in Debug UI-testing launches.
Its list transport supplies 100 deterministic pads and forwards all other requests to the SDK's in-process mock, never the live service.
Ordinary demos and shipping builds use the existing mock.
The budget is opt-in through the Performance plan; capture hardware, OS, build configuration and xcresult with each measurement.
This end-to-end budget complements the cold-launch metric.

## Local measurement

On 29 October 2026, the isolated Debug test populated all 100 rows in **2.669 seconds** on a MacBook Pro (Mac17,2), arm64, macOS 27.2 (26B123), built with Xcode 27.1.
The run passed the 10-second budget and retained its timing attachment in `first-account-100-pads-v4-20261029.xcresult`.
This measures mock-backed list population while Settings remains open; it does not measure live network latency or establish that the list is immediately interactive.
