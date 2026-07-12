//
//  CoderpadIPadUITests.swift
//  coderpadUITests
//
//  iPad smoke coverage for the primary coderpad.xcodeproj.
//

import XCTest

#if os(iOS)
    @MainActor
    final class CoderpadIPadUITests: XCTestCase {
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
        /// `expectation(for:)` API, which trips Swift strict-concurrency in a test case.
        private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if condition() { return true }
                _ = XCUIApplication().wait(for: .runningForeground, timeout: 0.2)
            }
            return condition()
        }

        /// Tapping a pad row shows its detail; the "Select a pad" placeholder goes away.
        func testTappingPadShowsDetail() {
            let app = launchSeeded()

            let firstPadTitle = app.staticTexts["Pairing: React Performance"]
            XCTAssertTrue(firstPadTitle.waitForExistence(timeout: 12),
                          "The seeded pads list should render on iPad.")

            let placeholder = app.staticTexts["Select a pad"]
            XCTAssertTrue(placeholder.exists, "Detail should start on the 'Select a pad' placeholder.")

            firstPadTitle.tap()

            XCTAssertTrue(waitUntil(timeout: 10) { !placeholder.exists },
                          "Selecting a pad should replace the placeholder with its detail.")

            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "pad-detail"
            shot.lifetime = .keepAlways
            add(shot)
        }

        /// The detail pane's Document Actions overflow menu exposes commands that live in
        /// the File menu on macOS.
        func testDocumentActionsMenu() {
            let app = launchSeeded()

            let firstPadTitle = app.staticTexts["Pairing: React Performance"]
            XCTAssertTrue(firstPadTitle.waitForExistence(timeout: 12))
            firstPadTitle.tap()

            let menu = app.buttons["Document Actions"]
            XCTAssertTrue(menu.waitForExistence(timeout: 10),
                          "The detail pane should offer a Document Actions menu on iPad.")
            menu.tap()

            for item in ["Print", "Export as Markdown", "Save Code"] {
                XCTAssertTrue(app.buttons[item].waitForExistence(timeout: 5),
                              "The Document Actions menu should contain '\(item)'.")
            }

            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "document-actions-menu"
            shot.lifetime = .keepAlways
            add(shot)

            app.tap()
        }

        /// The favorite star is visible and tappable on iPad; it is not hover-gated there.
        func testFavoriteStarIsTappable() {
            let app = launchSeeded()

            let padTitle = "Pairing: React Performance"
            XCTAssertTrue(app.staticTexts[padTitle].waitForExistence(timeout: 12))

            let star = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@ AND label BEGINSWITH[c] %@", padTitle, "Add")
            ).firstMatch
            XCTAssertTrue(star.waitForExistence(timeout: 5),
                          "The favorite star should be visible and hittable on iPad.")
            star.tap()

            let unstar = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@ AND label BEGINSWITH[c] %@", padTitle, "Remove")
            ).firstMatch
            XCTAssertTrue(unstar.waitForExistence(timeout: 5),
                          "Tapping the star should toggle the favorite state.")
        }
    }
#endif
