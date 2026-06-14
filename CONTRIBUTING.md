# Contributing

## Testing: keep the pyramid healthy

The test suite has three tiers, cheapest first. **Default new coverage to the
cheapest tier that can catch the regression**, so the suite stays fast and the
expensive tier stays thin.

| Tier | Where | Cost | Use it for |
| --- | --- | --- | --- |
| Unit | `coderpadTests/` (e.g. `coderpadTests+Models.swift`, `coderpadTests+PadFiltering.swift`, `coderpadTests+PadListLogic.swift`, `coderpadTests+SearchInterpreter.swift`) | Milliseconds | Logic, decoding, filtering, search, error mapping. Anything with no view involved. |
| Render | `coderpadTests/DesignSystemRenderTests.swift` | Fast (no app launch) | View-level regressions. Rasterize a view with `ImageRenderer` and assert it produces a valid, non-zero image. |
| XCUITest | `coderpadUITests/` | A full cold app launch each | A thin smoke layer only: does it launch, does the list paint, can you navigate. |

### Prefer a render test to a UI test

`DesignSystemRenderTests` shows the cheap substitute for many UI tests: rather
than booting the whole app to check a view behaves, render it in isolation via
`ImageRenderer` and assert it rasterizes (doesn't crash, doesn't collapse to
zero size). This needs no third-party snapshot library and keeps nothing to
re-record across OS or font-rendering changes.

```swift
let renderer = ImageRenderer(content: MyView(...))
renderer.scale = 2
#expect(renderer.nsImage?.size.width ?? 0 > 0)
```

### Reserve XCUITest for a smoke layer

Every XCUITest adds a cold launch, so the UI tier is where suite runtime creeps.
Resist adding more than the essentials — launch, first paint, basic navigation.
If a regression can be caught by a unit or render test, write that instead.

### Why

Fast feedback keeps the suite worth running on every change. When a pull request
reaches for a UI test, ask whether a unit or render test would prove the same
thing in a fraction of the time, and point here.

Use the [Swift Testing](https://developer.apple.com/documentation/testing/)
framework for unit and render tests, and `XCUIAutomation` for the UI smoke tier.
