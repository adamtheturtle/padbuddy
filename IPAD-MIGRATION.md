# iPad app migration

PadBuddy now ships its iPad build from the primary `coderpad.xcodeproj`.
The old xcodegen verification harness (`project-ipad.yml` generating
`PadBuddyiPad.xcodeproj`) has been retired.

## Current project shape

- The main `coderpad` target supports `iphoneos`, `iphonesimulator`, and `macosx`.
- `TARGETED_DEVICE_FAMILY` is set to `2` for iPad.
- The Sparkle package link is filtered to macOS only.
- The `RecentPadsWidgetExtension.appex` embed is filtered to macOS only.
- The `coderpadUITests` target is shared by macOS and iPad.

## iPad UI smoke tests

The former harness tests now live in `coderpadUITests/CoderpadIPadUITests.swift`
behind `#if os(iOS)`. They run against the seeded `-uiTesting` demo account and
cover:

- tapping a pad row replaces the "Select a pad" placeholder with detail content
- the iPad Document Actions menu exposes Print, Export as Markdown, and Save Code
- the favorite star is visible and toggles on iPad

The existing macOS UI flow tests remain in `coderpadUITests/coderpadUITests.swift`
behind `#if os(macOS)` because they use macOS-specific interaction APIs such as
`XCUIElement.click()`.
