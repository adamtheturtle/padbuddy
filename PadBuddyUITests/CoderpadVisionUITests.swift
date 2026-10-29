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
                "-showWelcome", "-uiTestingNoAccounts", "-uiTestingTextSize", "accessibility1",
                "-uiTestingWindowSize", "640x520"
            ])

            XCTAssertTrue(app.staticTexts["Welcome to PadBuddy"].waitForExistence(timeout: 10))
            assertUsable(app.staticTexts["Welcome to PadBuddy"], in: app)
            assertUsable(app.buttons["Add CoderPad Account"], in: app, mustBeHittable: true)
            capture("vision-welcome-narrow")
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
            let padSections = app.buttons["Overview"].firstMatch
            XCTAssertTrue(padSections.waitForExistence(timeout: 10))
            assertUsable(padSections, in: app)
            capture("vision-main-default")

            questions.tap()
            XCTAssertTrue(app.staticTexts["Select a question"].waitForExistence(timeout: 5))
            let question = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Two Sum"))
                .firstMatch
            XCTAssertTrue(question.waitForExistence(timeout: 10))
            assertUsable(question, in: app, mustBeHittable: true)
            question.tap()
            let description = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "Description")).firstMatch
            XCTAssertTrue(description.waitForExistence(timeout: 10))
            assertUsable(description, in: app, mustBeHittable: true)
            description.tap()
            capture("vision-question-detail")

            verifyAccountSettings(in: app)
        }

        private func verifyAccountSettings(in app: XCUIApplication) {
            let accountMenu = app.buttons["Switch account"].firstMatch
            XCTAssertTrue(accountMenu.waitForExistence(timeout: 5))
            accountMenu.tap()
            let manageAccounts = app.buttons["Manage Accounts…"]
            XCTAssertTrue(manageAccounts.waitForExistence(timeout: 5))
            manageAccounts.tap()

            let addAccount = app.buttons["Add Account"].firstMatch
            XCTAssertTrue(addAccount.waitForExistence(timeout: 5))
            assertUsable(addAccount, in: app, mustBeHittable: true)
            assertUsable(app.buttons["Done"], in: app, mustBeHittable: true)
            capture("vision-settings-accounts")

            let account = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fawlty Towers"))
                .firstMatch
            assertUsable(account, in: app, mustBeHittable: true)
            account.tap()
            XCTAssertTrue(app.secureTextFields["API Key"].waitForExistence(timeout: 5))
            capture("vision-settings-account-editor")
        }

        func testLargeTextAcrossWindowSizesAndAppearances() {
            for size in ["640x520", "1040x720", "1440x900"] {
                for appearance in ["light", "dark"] {
                    let app = launch(arguments: [
                        "-uiTesting", "-uiTestingSection", "pads", "-uiTestingWindowSize", size,
                        "-uiTestingTextSize", "accessibility1", "-general.appearance", appearance
                    ])
                    let pad = app.descendants(matching: .any)
                        .matching(NSPredicate(format: "label BEGINSWITH %@", "Pairing: React Performance")).firstMatch
                    XCTAssertTrue(pad.waitForExistence(timeout: 15))
                    let dimensions = size.split(separator: "x").compactMap { Double($0) }
                    XCTAssertEqual(primaryWindow(in: app).frame.width, dimensions[0], accuracy: 1)
                    XCTAssertEqual(primaryWindow(in: app).frame.height, dimensions[1], accuracy: 1)
                    assertUsable(pad, in: app, mustBeHittable: true)
                    assertUsable(app.buttons["Language"].firstMatch, in: app, mustBeHittable: true)
                    capture("vision-large-text-\(size)-\(appearance)")
                    app.terminate()
                }
            }
        }

        private func launch(arguments: [String]) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["-uiTesting"] + arguments.filter { $0 != "-uiTesting" }
            app.launch()

            let continueButton = app.buttons["Continue"]
            if continueButton.waitForExistence(timeout: 6) {
                continueButton.tap()
            }
            return app
        }

        private func launch(_ arguments: [String]) -> XCUIApplication {
            launch(arguments: arguments)
        }

        func testWelcomeContentFitsInTheSpatialWindow() {
            let app = launch(["-showWelcome", "-uiTestingNoAccounts"])
            let welcome = app.staticTexts["Welcome to PadBuddy"]
            let addAccount = app.buttons["Add CoderPad Account"]

            XCTAssertTrue(welcome.waitForExistence(timeout: 10))
            XCTAssertTrue(addAccount.exists)
            XCTAssertTrue(primaryWindow(in: app).frame.contains(welcome.frame))
            XCTAssertTrue(primaryWindow(in: app).frame.contains(addAccount.frame))
        }

        func testSeededPadsRenderInThePrimaryWindow() {
            let app = launch(["-uiTesting", "-uiTestingSection", "pads"])
            let pad = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Pairing: React Performance"))
                .firstMatch

            XCTAssertTrue(pad.waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts["Select a pad"].exists)
            XCTAssertTrue(primaryWindow(in: app).frame.contains(pad.frame))
        }

        private func primaryWindow(in app: XCUIApplication) -> XCUIElement {
            let settings = app.windows.containing(.button, identifier: "Done").firstMatch
            if settings.exists {
                return settings
            }
            let welcome = app.windows.containing(.staticText, identifier: "Welcome to PadBuddy").firstMatch
            if welcome.exists {
                return welcome
            }
            return app.windows.containing(.button, identifier: "Switch account").firstMatch
        }

        private func capture(_ name: String) {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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
            XCTAssertTrue(
                primaryWindow(in: app).frame.contains(element.frame),
                file: file,
                line: line
            )
            if mustBeHittable {
                XCTAssertTrue(element.isHittable, file: file, line: line)
            }
        }
    }
#endif
