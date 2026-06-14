//
//  coderpadUITests.swift
//  coderpadUITests
//
//  Created by Adam Dangoor on 03/05/2026.
//

import XCTest

/// End-to-end flows over the in-process demo account. Launching with `-uiTesting`
/// starts the app from a single in-memory demo account backed by the mock server
/// (no network, no Keychain writes — see `AccountsStore.isUITesting`), so these run
/// deterministically and offline.
///
/// Navigation uses the app's ⌘-number section shortcuts rather than clicking sidebar
/// rows: menu key-equivalents are routed by AppKit regardless of window focus, so
/// they're far more reliable in a headless CI runner than synthesized mouse clicks.
final class CoderpadUITests: XCTestCase {
    private static let listLoadTimeout: TimeInterval = 30

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchDemoApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]
        app.launch()
        app.activate()
        return app
    }

    /// Each pad row is a single accessibility element whose label starts with the
    /// pad title (see `PadRow.accessibilityLabel`), so match on a label prefix.
    @MainActor
    private func padRow(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    /// The core navigation flow in a single cold launch: the seeded Pads paint, ⌘2
    /// switches to Questions (and they load), and ⌘1 returns to Pads with the list
    /// restored. Collapses what were three separate tests — each re-launching and
    /// re-waiting the same initial Pads paint — into one launch, since the
    /// round-trip is a superset of the other two. UI tests stay a thin smoke layer;
    /// the unit + render tiers carry the real coverage.
    @MainActor
    func testSectionNavigationFlow() {
        let app = launchDemoApp()

        // Pads paint on launch.
        XCTAssertTrue(padRow("Onsite: Jane Doe", in: app).waitForExistence(timeout: Self.listLoadTimeout),
                      "A seeded demo pad should appear once the list loads")
        XCTAssertTrue(padRow("Phone screen: Sam Lee", in: app).exists,
                      "Other seeded demo pads should be listed too")

        // ⌘2 → Questions, and the seeded questions load there.
        app.typeKey("2", modifierFlags: .command) // View ▸ Questions
        XCTAssertTrue(app.staticTexts["FizzBuzz"].waitForExistence(timeout: Self.listLoadTimeout),
                      "A seeded demo question should appear after switching to Questions")

        // ⌘1 → back to Pads restores the list.
        app.typeKey("1", modifierFlags: .command) // back to Pads
        XCTAssertTrue(padRow("Onsite: Jane Doe", in: app).waitForExistence(timeout: Self.listLoadTimeout),
                      "Returning to Pads should show the pad list again")
    }

    @MainActor
    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
