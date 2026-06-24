//
//  PadBuddyiPadUITests.swift
//  PadBuddyiPad (verification harness)
//
//  Drives the generated iPad app on the simulator to verify the core interactions that
//  cannot be checked from screenshots alone: tapping a pad row selects it and shows its
//  detail in the NavigationSplitView detail column, and the favorite star toggles. Runs
//  against the seeded `-uiTesting` demo so the data is deterministic.
//

import XCTest

@MainActor
final class PadBuddyiPadUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        // Dismiss the "What's New" sheet if it appears on first launch.
        let continueButton = app.buttons["Continue"]
        if continueButton.waitForExistence(timeout: 6) {
            continueButton.tap()
        }
        return app
    }

    /// Polls until `condition` holds or the timeout elapses, without the predicate-based
    /// `expectation(for:)` API (which trips Swift 6 strict-concurrency in a test case).
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            _ = XCUIApplication().wait(for: .runningForeground, timeout: 0.2)
        }
        return condition()
    }

    /// Tapping a pad row shows its detail (the "Select a pad" placeholder goes away).
    func testTappingPadShowsDetail() throws {
        let app = launchSeeded()

        let firstPadTitle = app.staticTexts["Pairing: React Performance"]
        XCTAssertTrue(firstPadTitle.waitForExistence(timeout: 12),
                      "The seeded pads list should render on iPad.")

        // The detail column starts on the placeholder before any selection.
        let placeholder = app.staticTexts["Select a pad"]
        XCTAssertTrue(placeholder.exists, "Detail should start on the 'Select a pad' placeholder.")

        // Tap the row. The title text is hit-transparent (it falls through to row
        // selection), so tapping its frame selects the row.
        firstPadTitle.tap()

        // After selection the placeholder should disappear as the detail loads.
        XCTAssertTrue(waitUntil(timeout: 10) { !placeholder.exists },
                      "Selecting a pad should replace the placeholder with its detail.")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "pad-detail"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The favorite star is visible and tappable on iPad (it is not hover-gated there).
    func testFavoriteStarIsTappable() throws {
        let app = launchSeeded()

        let firstPadTitle = app.staticTexts["Pairing: React Performance"]
        XCTAssertTrue(firstPadTitle.waitForExistence(timeout: 12))

        // The star buttons carry an accessibility label of the form "Add <title> to Favorites".
        let star = app.buttons["Add Pairing: React Performance to Favorites"]
        XCTAssertTrue(star.waitForExistence(timeout: 5),
                      "The favorite star should be visible/hittable on iPad.")
        star.tap()

        // After tapping, the label flips to the "Remove ..." form.
        let unstar = app.buttons["Remove Pairing: React Performance from Favorites"]
        XCTAssertTrue(unstar.waitForExistence(timeout: 5),
                      "Tapping the star should toggle the favorite state.")
    }
}
