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
final class coderpadUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchDemoApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]
        app.launch()
        return app
    }

    /// Each pad row is a single accessibility element whose label starts with the
    /// pad title (see `PadRow.accessibilityLabel`), so match on a label prefix
    /// rather than an exact static-text title.
    private func padRow(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    /// Browse pads: the demo account's seeded pads appear in the list.
    @MainActor
    func testDemoPadsAppearInList() throws {
        let app = launchDemoApp()
        XCTAssertTrue(padRow("Onsite: Jane Doe", in: app).waitForExistence(timeout: 15),
                      "A seeded demo pad should appear once the list loads")
        XCTAssertTrue(padRow("Phone screen: Sam Lee", in: app).exists,
                      "Other seeded demo pads should be listed too")
    }

    /// Open a pad in the in-window browser: selecting a pad reveals its detail
    /// toolbar actions, and "Open Pad" brings up the embedded browser (we assert on
    /// its pop-out control, which appears with the browser chrome — without waiting
    /// on web content, which would need the network).
    @MainActor
    func testOpeningAPadInTheInWindowBrowser() throws {
        let app = launchDemoApp()
        let pad = padRow("Phone screen: Sam Lee", in: app)
        XCTAssertTrue(pad.waitForExistence(timeout: 15))
        pad.click()

        let openPad = app.buttons["Open Pad"]
        XCTAssertTrue(openPad.waitForExistence(timeout: 10),
                      "Selecting a pad should reveal its detail toolbar actions")
        openPad.click()

        XCTAssertTrue(app.buttons["Open in separate window"].waitForExistence(timeout: 10),
                      "The in-window pad browser should open")
    }

    /// Switch sections: the sidebar moves from Pads to Questions, and the demo
    /// questions load.
    @MainActor
    func testSwitchToQuestionsSection() throws {
        let app = launchDemoApp()
        // Wait for first paint (pads) before navigating.
        _ = app.staticTexts["Onsite: Jane Doe"].waitForExistence(timeout: 15)
        let questions = app.buttons["Questions"]
        XCTAssertTrue(questions.waitForExistence(timeout: 5))
        questions.click()
        XCTAssertTrue(app.staticTexts["FizzBuzz"].waitForExistence(timeout: 15),
                      "A seeded demo question should appear after switching sections")
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
