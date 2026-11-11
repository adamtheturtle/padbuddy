import XCTest

#if os(macOS)
    /// Toolbar construction must not invalidate AppKit's saved-frame layout pass.
    /// This needs a real application relaunch; a render test cannot restore NSWindows.
    final class PadBuddyWindowRestorationUITests: XCTestCase {
        @MainActor
        func testMainWindowRestoration() {
            continueAfterFailure = false
            let app = XCUIApplication()
            app.launchArguments = [
                "-ApplePersistenceIgnoreState", "YES",
                "-uiTesting", "-uiTestingKeepDefaultWindowSize",
                "-uiTestingSection", "pads", "-NSQuitAlwaysKeepsWindows", "YES"
            ]
            app.launch()
            app.showPadBuddyMainWindow()
            assertPadList(in: app)
            app.typeKey("2", modifierFlags: .command)
            XCTAssertTrue(app.searchFields["Search questions"].waitForExistence(timeout: 30))

            // Quit through AppKit so it writes the window-restoration archive.
            app.typeKey("q", modifierFlags: .command)
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))

            // Keep the archive on the second launch. The old toolbar crashed inside
            // NSWindow.restoreStateWithCoder before the list could be used again.
            app.launchArguments = Array(app.launchArguments.dropFirst(2))
            app.launch()
            // AppKit can retain its crash-recovery prompt from an earlier run.
            // Choose restoration explicitly instead of bypassing the failing path.
            let reopen = app.buttons["Reopen"]
            if reopen.waitForExistence(timeout: 3) {
                reopen.click()
            }
            app.showPadBuddyMainWindow()
            app.typeKey("1", modifierFlags: .command)
            assertPadList(in: app)
            XCTAssertNotEqual(app.state, .notRunning)
        }

        @MainActor
        private func assertPadList(in app: XCUIApplication) {
            let pad = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Onsite: Senior Backend Engineer")).firstMatch
            XCTAssertTrue(pad.waitForExistence(timeout: 30))
        }
    }
#endif
