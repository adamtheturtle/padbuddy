import XCTest

#if os(macOS)
    extension XCUIApplication {
        @MainActor func addPadBuddyDemoAccountFromWelcome() {
            XCTAssertTrue(staticTexts["Welcome to PadBuddy"].waitForExistence(timeout: 10))
            let add = buttons["Add CoderPad Account"].firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 5))
            add.click()
            let key = secureTextFields["API Key"]
            XCTAssertTrue(key.waitForExistence(timeout: 10))
            key.click()
            key.typeText("demo")
            let validate = buttons["Validate API Key"]
            XCTAssertTrue(validate.waitForExistence(timeout: 5))
            validate.click()
            finishPadBuddyAccountSetup(firstPad: "Onsite: Senior Backend Engineer")
        }

        @MainActor func finishPadBuddyAccountSetup(firstPad: String) {
            let row = descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", firstPad)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 30))
            let settings = windows["com_apple_SwiftUI_Settings_window"]
            if settings.exists {
                settings.buttons["_XCUI:CloseWindow"].click()
            }
        }

        /// XCUITest may launch the menu-bar process without an initial document event.
        /// Use the app's real command to present its single main window in that case.
        @MainActor func showPadBuddyMainWindow() {
            guard !windows["main"].waitForExistence(timeout: 3) else { return }

            menuBars.menuBarItems["Window"].click()
            let open = menuItems["Open Main Window"]
            XCTAssertTrue(open.waitForExistence(timeout: 3))
            open.click()
            XCTAssertTrue(windows["main"].waitForExistence(timeout: 10))
        }
    }
#endif
