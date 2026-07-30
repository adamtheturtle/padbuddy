//
//  CoderpadIPadUITests.swift
//  coderpadUITests
//
//  iPad smoke coverage for the primary coderpad.xcodeproj.
//

import XCTest

#if os(iOS)
    import UIKit

    @MainActor
    final class CoderpadIPadUITests: XCTestCase {
        override func setUpWithError() throws {
            continueAfterFailure = false
        }

        private func launchSeeded(
            section: String? = nil,
            appearance: String? = nil
        ) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["-uiTesting"]
            app.launchArguments += ["-uiTestingSection", section ?? "pads"]
            if let appearance {
                // Keep mobile marketing captures deterministic and in step with the
                // macOS capture path. The app reads this AppStorage preference at launch.
                app.launchArguments += ["-general.appearance", appearance]
            }
            app.launch()

            // Dismiss the "What's New" sheet if it appears on first launch.
            let continueButton = app.buttons["Continue"]
            if continueButton.waitForExistence(timeout: 6) {
                continueButton.tap()
            }
            return app
        }

        /// Produces the website's seeded, PII-free iPad/iPhone hero in both
        /// appearances. The same test runs against each simulator destination; using
        /// the device idiom in the attachment name lets the export script combine both
        /// result bundles without relying on simulator-specific filenames.
        func testCaptureWebsiteLightDarkScreenshots() throws {
            try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTURE_SCREENSHOTS"] != nil)

            let platform: String
            switch UIDevice.current.userInterfaceIdiom {
            case .pad:
                platform = "ipad"
                XCUIDevice.shared.orientation = .landscapeLeft

            case .phone:
                platform = "iphone"
                XCUIDevice.shared.orientation = .portrait

            default:
                throw XCTSkip("Website mobile screenshots require an iPad or iPhone simulator.")
            }

            for appearance in ["dark", "light"] {
                let app = launchSeeded(appearance: appearance)
                if platform == "ipad" {
                    navigateToPads(in: app, platform: platform)
                    let pad = seededPad(in: app)
                    XCTAssertTrue(
                        pad.waitForExistence(timeout: 12),
                        "The seeded demo pads should render on iPad in \(appearance) mode."
                    )
                    let placeholder = app.staticTexts["Select a pad"]
                    pad.tap()
                    XCTAssertTrue(
                        waitUntil(timeout: 10) { !placeholder.exists },
                        "Selecting the seeded iPad pad should replace the detail placeholder."
                    )
                } else {
                    navigateToPads(in: app, platform: platform)
                    XCTAssertTrue(
                        seededPad(in: app).waitForExistence(timeout: 12),
                        "The seeded demo pads should render on iPhone in \(appearance) mode."
                    )
                }
                // Allow the seeded list, navigation chrome, and appearance transition
                // to settle before taking the full-screen marketing capture.
                usleep(1_000_000)
                capture("website-\(platform)-\(appearance)", app: app)
                app.terminate()
            }
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

        private func capture(_ name: String, app: XCUIApplication) {
            let window = app.windows.firstMatch
            XCTAssertTrue(window.waitForExistence(timeout: 5))
            let shot = XCTAttachment(screenshot: window.screenshot())
            shot.name = name
            shot.lifetime = .keepAlways
            add(shot)
        }

        private func seededPad(in app: XCUIApplication) -> XCUIElement {
            // Rows combine their title and metadata into one accessibility element, so
            // the title is a label prefix rather than a standalone StaticText.
            app.descendants(matching: .any)
                .matching(NSPredicate(
                    format: "label BEGINSWITH %@",
                    "Pairing: React Performance"
                ))
                .firstMatch
        }

        private func seededQuestion(in app: XCUIApplication) -> XCUIElement {
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Two Sum"))
                .firstMatch
        }

        private func navigateToPads(in app: XCUIApplication, platform: String) {
            let pads = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "Pads"))
                .firstMatch
            var openedSidebarOverlay = false

            if platform == "ipad", !pads.waitForExistence(timeout: 1) {
                // In portrait, NavigationSplitView starts with its sidebar collapsed.
                // Its native sidebar toggle is the leading toolbar button.
                let sidebarToggle = app.buttons.firstMatch
                if sidebarToggle.waitForExistence(timeout: 2) {
                    sidebarToggle.tap()
                    openedSidebarOverlay = true
                }
            }

            if pads.waitForExistence(timeout: 3), pads.isHittable {
                pads.tap()
            }

            if openedSidebarOverlay {
                // Selecting the section does not dismiss the portrait sidebar overlay.
                // The system reports its Hide Sidebar button with an off-screen hit
                // point during the overlay animation, so tap the stable toolbar
                // position directly after the transition settles.
                usleep(500_000)
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.272, dy: 0.04)).tap()
            }
        }

        /// Produces the PII-free 13-inch iPad App Store set from the seeded demo.
        func testCaptureAppStoreScreenshots() throws {
            try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTURE_SCREENSHOTS"] != nil)
            XCUIDevice.shared.orientation = .landscapeLeft
            let app = launchSeeded()
            let padRow = seededPad(in: app)
            XCTAssertTrue(padRow.waitForExistence(timeout: 12))

            capture("ipad-main-split", app: app)
            padRow.tap()
            XCTAssertTrue(app.buttons["Document Actions"].waitForExistence(timeout: 10))
            capture("ipad-pad-detail", app: app)
        }

        func testCaptureAppStoreQuestionScreenshots() throws {
            try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTURE_SCREENSHOTS"] != nil)
            XCUIDevice.shared.orientation = .landscapeLeft
            let app = launchSeeded(section: "questions")
            XCTAssertTrue(seededQuestion(in: app).waitForExistence(timeout: 12))
            capture("ipad-questions-list", app: app)

            let search = app.searchFields.firstMatch
            if search.waitForExistence(timeout: 3) {
                search.tap()
                search.typeText("Two Sum")
            } else {
                let filters = app.buttons["Suggested question filters"]
                XCTAssertTrue(filters.waitForExistence(timeout: 5))
                filters.tap()
            }
            XCTAssertTrue(seededQuestion(in: app).waitForExistence(timeout: 5))
            capture("ipad-filter-search", app: app)
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

        /// Long-press exposes the same row actions as the AppKit context menu (#576).
        func testPadRowLongPressShowsContextActions() {
            let app = launchSeeded()
            let title = app.staticTexts["Pairing: React Performance"]
            XCTAssertTrue(title.waitForExistence(timeout: 12))

            title.press(forDuration: 1.2)

            XCTAssertTrue(app.buttons["Copy Pad ID"].waitForExistence(timeout: 5),
                          "A pad long-press should expose its context actions on iPad.")
            let delete = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Delete")).firstMatch
            XCTAssertTrue(delete.exists,
                          "The context menu should include the destructive row action.")
        }

        /// Core list actions must remain visible in touch-first toolbar controls (#576/#686).
        func testPadToolbarExposesCreationFiltersAndSort() {
            let app = launchSeeded()
            XCTAssertTrue(app.staticTexts["Pairing: React Performance"].waitForExistence(timeout: 12))

            for label in ["New Pad", "Suggested pad filters", "Sort pads"] {
                XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 5),
                              "The iPad pad toolbar should expose \(label).")
            }
        }
    }
#endif
