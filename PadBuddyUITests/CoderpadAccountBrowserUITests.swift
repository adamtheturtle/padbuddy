import XCTest

#if os(macOS)
    final class CoderpadAccountBrowserUITests: XCTestCase {
        private static let listLoadTimeout: TimeInterval = 30

        override func setUpWithError() throws {
            continueAfterFailure = false
        }

        @MainActor
        private func row(_ title: String, in app: XCUIApplication) -> XCUIElement {
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        }

        /// Covers the first-run account path with the same in-process demo backend as
        /// the list smoke. The special empty launch remains persistence-free, but the
        /// user-visible flow is real: empty state -> Settings -> account editor ->
        /// validation -> active account -> loaded pads.
        @MainActor
        func testFirstRunCanAddDemoAccount() {
            let app = XCUIApplication()
            app.launchArguments = [
                "-ApplePersistenceIgnoreState", "YES", "-uiTestingWindowSize", "1440x900",
                "-uiTesting", "-uiTestingNoAccounts", "-uiTestingSection", "pads"
            ]
            app.launch()
            app.showPadBuddyMainWindow()

            let emptyState = app.staticTexts["Welcome to PadBuddy"]
            XCTAssertTrue(emptyState.waitForExistence(timeout: 10),
                          "A persistence-free empty launch should show first-run account setup")

            let addAccount = app.buttons["Add CoderPad Account"].firstMatch
            XCTAssertTrue(addAccount.waitForExistence(timeout: 5))
            addAccount.click()

            let apiKey = app.secureTextFields["API Key"]
            XCTAssertTrue(apiKey.waitForExistence(timeout: 10),
                          "The first-run action should open the account editor in Settings")
            apiKey.click()
            apiKey.typeText("demo")

            let validate = app.buttons["Validate API Key"]
            XCTAssertTrue(validate.waitForExistence(timeout: 5))
            validate.click()
            app.finishPadBuddyAccountSetup(firstPad: "Onsite: Senior Backend Engineer")

            XCTAssertTrue(
                row("Onsite: Senior Backend Engineer", in: app)
                    .waitForExistence(timeout: Self.listLoadTimeout),
                "Adding the deterministic demo should select it and load its pads"
            )
        }

        /// Exercises the row's real context-menu browser action while keeping the
        /// runner in front. The app reports the URL through a UI-test-only distributed
        /// notification instead of opening Safari, so the assertion covers routing and
        /// account/server URL resolution without depending on the machine's browser.
        @MainActor
        func testPadContextMenuHandsExactURLToBrowser() {
            let notificationName = Notification.Name("com.coderpad.app.uiTestingBrowserOpen")
            let opened = expectation(forNotification: notificationName,
                                     object: nil,
                                     notificationCenter: DistributedNotificationCenter.default()) { note in
                note.object as? String == "https://app.coderpad.io/DEMOABC1"
            }

            let app = XCUIApplication()
            app.launchArguments = [
                "-ApplePersistenceIgnoreState", "YES", "-uiTestingWindowSize", "1440x900",
                "-uiTesting", "-uiTestingNoAccounts", "-uiTestingCaptureBrowserOpen", "-uiTestingSection", "pads"
            ]
            app.launch()
            app.showPadBuddyMainWindow()

            app.addPadBuddyDemoAccountFromWelcome()

            let pad = row("Onsite: Senior Backend Engineer", in: app)
            XCTAssertTrue(pad.waitForExistence(timeout: Self.listLoadTimeout))
            pad.rightClick()

            let open = app.menuItems["Open Pad"]
            XCTAssertTrue(open.waitForExistence(timeout: 5))
            open.click()

            wait(for: [opened], timeout: 10)
        }
    }
#endif
