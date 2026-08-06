//
//  CoderpadVisionUITests.swift
//  PadBuddyUITests
//
//  Opt-in spatial UI smoke coverage. Run through the CI workflow dispatch or
//  the documented targeted xcodebuild command; it is intentionally not part of
//  the default macOS/iOS UI run.
//

import XCTest

#if os(visionOS)
    @MainActor
    final class CoderpadVisionUITests: XCTestCase {
        override func setUpWithError() throws {
            continueAfterFailure = false
        }

        func testNarrowWelcomeState() {
            let app = launch(arguments: [
                "-uiTesting",
                "-showWelcome",
                "-uiTestingWindowSize", "640x520"
            ])

            XCTAssertTrue(app.staticTexts["Welcome to PadBuddy"].waitForExistence(timeout: 10))
            assertUsable(app.staticTexts["Welcome to PadBuddy"], in: app)
            assertUsable(app.buttons["Add CoderPad Account"], in: app, mustBeHittable: true)
            capture("vision-welcome-narrow", app: app)
        }

        func testDefaultSeededMainWindowAndAccountSettings() {
            let app = launch(arguments: ["-uiTesting", "-uiTestingSection", "pads"])
            let pad = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Pairing: React Performance"))
                .firstMatch

            let pads = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "Pads"))
                .firstMatch
            let questions = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "Questions"))
                .firstMatch
            XCTAssertTrue(pads.waitForExistence(timeout: 10))
            assertUsable(pads, in: app, mustBeHittable: true)
            assertUsable(questions, in: app, mustBeHittable: true)
            XCTAssertTrue(app.staticTexts["Select a pad"].waitForExistence(timeout: 5))
            assertUsable(app.staticTexts["Select a pad"], in: app)
            XCTAssertTrue(pad.waitForExistence(timeout: 10))
            assertUsable(pad, in: app, mustBeHittable: true)

            pad.tap()
            XCTAssertTrue(app.staticTexts["Overview"].waitForExistence(timeout: 5))
            assertUsable(app.staticTexts["Overview"], in: app)
            capture("vision-main-default", app: app)

            questions.tap()
            XCTAssertTrue(app.staticTexts["Select a question"].waitForExistence(timeout: 5))
            let question = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Two Sum"))
                .firstMatch
            XCTAssertTrue(question.waitForExistence(timeout: 10))
            assertUsable(question, in: app, mustBeHittable: true)
            question.tap()
            XCTAssertTrue(app.staticTexts["Description"].waitForExistence(timeout: 5))
            assertUsable(app.staticTexts["Description"], in: app)
            capture("vision-question-detail", app: app)

            let settings = app.buttons["Settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            settings.tap()

            let accounts = app.buttons["Accounts"]
            XCTAssertTrue(accounts.waitForExistence(timeout: 5))
            accounts.tap()
            XCTAssertTrue(app.staticTexts["Accounts"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Done"].exists)

            let settingsWindow = app.windows.firstMatch
            XCTAssertTrue(settingsWindow.exists)
            XCTAssertGreaterThan(settingsWindow.frame.width, 0)
            XCTAssertGreaterThan(settingsWindow.frame.height, 0)
            capture("vision-settings-accounts", app: app)
        }

        private func launch(arguments: [String]) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = arguments
            app.launch()

            let continueButton = app.buttons["Continue"]
            if continueButton.waitForExistence(timeout: 2) {
                continueButton.tap()
            }
            return app
        }

        private func capture(_ name: String, app: XCUIApplication) {
            let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            shot.name = name
            shot.lifetime = .keepAlways
            add(shot)
        }

        private func assertUsable(
            _ element: XCUIElement,
            in app: XCUIApplication,
            mustBeHittable: Bool = false,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertTrue(element.exists, file: file, line: line)
            XCTAssertGreaterThan(element.frame.width, 0, file: file, line: line)
            XCTAssertGreaterThan(element.frame.height, 0, file: file, line: line)
            XCTAssertTrue(element.frame.intersects(app.windows.firstMatch.frame), file: file, line: line)
            if mustBeHittable {
                XCTAssertTrue(element.isHittable, file: file, line: line)
            }
        }
    }
#endif
