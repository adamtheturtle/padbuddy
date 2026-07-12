//
//  coderpadUITests.swift
//  coderpadUITests
//
//  Created by Adam Dangoor on 03/05/2026.
//

import XCTest

#if os(macOS)
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

        /// The screenshot/asset-capture tests drive the live GUI and click rows to pose
        /// each shot, so they're inherently focus-flaky in a shared session and assert
        /// nothing about correctness - they exist only to regenerate marketing assets.
        /// Gate them behind an explicit opt-in (like `RUN_LAUNCH_PERF_TESTS` does for the
        /// launch metric) so a normal test pass - local or CI - skips them and stays
        /// green; run them deliberately with `CAPTURE_SCREENSHOTS=1` to refresh assets.
        private func skipUnlessCapturingScreenshots() throws {
            try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTURE_SCREENSHOTS"] != nil,
                              "Set CAPTURE_SCREENSHOTS to run the asset-capture screenshots.")
        }

        /// Some interaction tests drive the app with the keyboard (e.g. ⌘K to open the
        /// command palette), which only reaches the app while it is the frontmost
        /// application. In a contended GUI session - parallel runs, or several agents
        /// sharing one desktop - another app can win focus the instant the keystroke is
        /// synthesized, so the input is dropped and the test flakes. Gate these behind an
        /// explicit opt-in so the default pass stays green; run them deliberately with
        /// `RUN_FOCUS_SENSITIVE_UI_TESTS=1` on a quiet machine to verify the interaction.
        private func skipUnlessRunningFocusSensitiveUITests() throws {
            try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_FOCUS_SENSITIVE_UI_TESTS"] != nil,
                              "Set RUN_FOCUS_SENSITIVE_UI_TESTS to run focus-sensitive keyboard-driven UI tests.")
        }

        @MainActor
        private func launchDemoApp(textSize: String? = nil, appearance: String? = nil) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments += ["-uiTesting"]
            // Pin a larger Dynamic Type size for the marketing capture so the UI text
            // reads clearly on the website/App Store, without cropping or zooming.
            if let textSize {
                app.launchArguments += ["-uiTestingTextSize", textSize]
            }
            // Force the app-wide appearance for the App Store light/dark shots. The app
            // reads this preference (`@AppStorage(GeneralSettings.Key.appearance)`) once
            // at launch, and the NSArgumentDomain default `-general.appearance <value>`
            // overrides it for this process only — no production code path is involved.
            if let appearance {
                app.launchArguments += ["-general.appearance", appearance]
            }
            app.launch()
            app.activate()
            return app
        }

        /// Both pad and question rows are a single accessibility element whose label
        /// starts with the row's title (see `PadRow`/`QuestionRow` — each folds its
        /// title + metadata into one combined `accessibilityLabel` since the #439
        /// NSTableView migration), so match on a label prefix rather than a discrete
        /// `staticTexts[title]`, which the combined element no longer exposes.
        @MainActor
        private func row(_ title: String, in app: XCUIApplication) -> XCUIElement {
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
            XCTAssertTrue(row("Onsite: Senior Backend Engineer", in: app).waitForExistence(timeout: Self.listLoadTimeout),
                          "A seeded demo pad should appear once the list loads")
            // Wait for the second pad rather than checking `.exists` instantaneously: the
            // rows don't all render in the same frame, so a bare existence check races the
            // list's first layout and flakes under load.
            XCTAssertTrue(row("Phone screen: Frontend Engineer", in: app).waitForExistence(timeout: Self.listLoadTimeout),
                          "Other seeded demo pads should be listed too")

            // ⌘2 → Questions, and the seeded questions load there.
            app.typeKey("2", modifierFlags: .command) // View ▸ Questions
            XCTAssertTrue(row("Two Sum", in: app).waitForExistence(timeout: Self.listLoadTimeout),
                          "A seeded demo question should appear after switching to Questions")

            // ⌘1 → back to Pads restores the list.
            app.typeKey("1", modifierFlags: .command) // back to Pads
            XCTAssertTrue(row("Onsite: Senior Backend Engineer", in: app).waitForExistence(timeout: Self.listLoadTimeout),
                          "Returning to Pads should show the pad list again")
        }

        /// Captures real, PII-free screenshots of the seeded demo account for the
        /// marketing site (`docs/`) and the App Store listing. It drives the app into
        /// a few representative states and attaches a PNG of the main window for each
        /// to the test result (the runner is sandboxed, so we can't write to disk
        /// directly); export them from the `.xcresult` bundle afterwards.
        ///
        /// Skipped on CI (the headless runner has no display worth shooting and we
        /// don't want to pay the window-capture cost nightly); run it locally via the
        /// test navigator or `RunSomeTests` to refresh the assets.
        @MainActor
        func testCaptureMarketingScreenshots() throws {
            try skipUnlessCapturingScreenshots()

            let app = launchDemoApp()

            // Pads paint on launch; wait for them, then give the window a beat to grow
            // to full size (`applicationDidBecomeActive` resizes it under `-uiTesting`).
            XCTAssertTrue(row("Onsite: Senior Backend Engineer", in: app).waitForExistence(timeout: Self.listLoadTimeout),
                          "A seeded demo pad should appear once the list loads")
            usleep(3_000_000)

            // Pads list with nothing selected: the sidebar + populated list before the
            // user picks anything — the "browse your pads" App Store shot (#62).
            captureScreenshot("pads-list", in: app)

            // Pads with a pad selected: the Mail-style three-column layout (sidebar +
            // list + populated detail) — the hero shot for #505.
            clickRow("Onsite: Senior Backend Engineer", in: app)
            usleep(1_500_000) // let the detail pane settle
            captureScreenshot("pads-detail", in: app)

            // Questions section with a question selected — a feature shot for #506.
            app.typeKey("2", modifierFlags: .command) // View ▸ Questions
            XCTAssertTrue(row("Two Sum", in: app).waitForExistence(timeout: Self.listLoadTimeout),
                          "A seeded demo question should appear after switching to Questions")
            clickRow("Two Sum", in: app)
            usleep(1_500_000)
            captureScreenshot("questions-detail", in: app)

            // Organization directory: the seeded team/member data renders each person's
            // name as static text, so wait on one before shooting — an org-overview App
            // Store shot (#62).
            app.typeKey("3", modifierFlags: .command) // View ▸ Organization
            XCTAssertTrue(row("Basil Fawlty", in: app).waitForExistence(timeout: Self.listLoadTimeout),
                          "A seeded demo org member should appear after switching to Organization")
            usleep(1_500_000)
            captureScreenshot("organization", in: app)

            // The website hero again, but with a larger Dynamic Type size so the UI text
            // is legible at the on-page size (replaces docs/assets/screenshot-pads). A
            // fresh launch is needed because Dynamic Type is fixed at the window's launch.
            //
            // Capture the populated Pads list rather than clicking into a pad's detail:
            // under accessibility1 the larger text drops the split view's list column out
            // of the hit-testable hierarchy after the one-shot window resize, so the row
            // click is unreliable here (the dark detail shot already covers the detail
            // layout). Same click-free rationale as testCaptureAppStoreLightDark.
            app.terminate()
            let large = launchDemoApp(textSize: "accessibility1")
            XCTAssertTrue(row("Onsite: Senior Backend Engineer", in: large).waitForExistence(timeout: Self.listLoadTimeout),
                          "The seeded pads should reload in the large-text launch")
            usleep(3_000_000)
            captureScreenshot("pads-list-large", in: large)
        }

        /// Capture the frontmost window (falling back to the whole app) as a
        /// keep-always screenshot attachment named `name`.
        @MainActor
        private func captureScreenshot(_ name: String, in app: XCUIApplication) {
            let window = app.windows.firstMatch
            let shot = window.exists ? window.screenshot() : app.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        /// Click a row by title, re-querying right before the click so a transient
        /// relayout (e.g. the one-shot window resize) can't leave us with a stale
        /// element reference.
        @MainActor
        private func clickRow(_ title: String, in app: XCUIApplication) {
            let element = row(title, in: app)
            _ = element.waitForExistence(timeout: Self.listLoadTimeout)
            // Wait until the layout has settled enough for the row to be hittable;
            // the one-shot window resize can otherwise stale the element snapshot
            // mid-click.
            let deadline = Date().addingTimeInterval(5)
            while !element.isHittable, Date() < deadline {
                usleep(100_000)
            }
            element.click()
        }

        /// App Store appearance shots (#62): the seeded pads-detail hero captured in both
        /// dark and light mode. Each appearance needs its own cold launch because the app
        /// reads the appearance preference once at startup; `launchDemoApp(appearance:)`
        /// drives it via the `-general.appearance` argument-domain default. Skipped on CI
        /// like the other capture tests.
        ///
        /// Captures the populated Pads list (sidebar + list, nothing selected) rather than
        /// clicking into a pad's detail: the window capture itself is reliable even with
        /// other app instances running, but an interactive row *click* needs the test app
        /// frontmost and is focus-flaky in a shared GUI session. The detail layout is
        /// already covered by the existing dark detail shot.
        @MainActor
        func testCaptureAppStoreLightDark() throws {
            try skipUnlessCapturingScreenshots()

            for (appearance, name) in [("dark", "appstore-dark"), ("light", "appstore-light")] {
                let app = launchDemoApp(appearance: appearance)

                // Pads paint on launch; wait for them, then let the one-shot window resize
                // (`applicationDidBecomeActive`) settle before capturing.
                XCTAssertTrue(
                    row("Onsite: Senior Backend Engineer", in: app).waitForExistence(timeout: Self.listLoadTimeout),
                    "A seeded demo pad should appear once the list loads (\(appearance))"
                )
                usleep(3_000_000)

                // The shot is a whole-display grab, so the test app must be frontmost or
                // another window bleeds in. Re-activate right before capturing (a sibling
                // app may have raised a window during the settle above).
                app.activate()
                usleep(750_000)

                let window = app.windows.firstMatch
                let shot = window.exists ? window.screenshot() : app.screenshot()
                let attachment = XCTAttachment(screenshot: shot)
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)

                app.terminate()
            }
        }

        /// The command palette's arrow keys move the selection (#532). The focused search
        /// field's field editor used to swallow the arrows, so a local key monitor now drives
        /// the selection; each row is a single accessibility element and the selected one
        /// carries `.isSelected`, so we can read which row is highlighted directly (no
        /// screenshot, and the app needn't stay frontmost for the query). The window is
        /// brought frontmost with `activate()` so ⌘K reaches it.
        @MainActor
        func testCommandPaletteArrowKeysMoveSelection() throws {
            try skipUnlessRunningFocusSensitiveUITests()

            let app = launchDemoApp()

            let firstPad = row("Onsite: Senior Backend Engineer", in: app)
            XCTAssertTrue(firstPad.waitForExistence(timeout: Self.listLoadTimeout),
                          "Pads should load before opening the palette")
            // Bring the window frontmost so ⌘K is delivered. `activate()` is focus-reliable
            // and, unlike a synthesized row click, doesn't go stale when a sibling app
            // raises a window in a shared GUI session (the old click's flakiness source).
            app.activate()

            app.typeKey("k", modifierFlags: .command) // Go ▸ Go to Anything…

            // The selected palette row is the only *button* reporting `isSelected` (the
            // sidebar's selected row is a list cell, not a button).
            let selectedRow = app.buttons.matching(NSPredicate(format: "isSelected == true")).firstMatch
            XCTAssertTrue(selectedRow.waitForExistence(timeout: 10),
                          "The palette should open with a selected row")
            let firstLabel = selectedRow.label

            app.typeKey(.downArrow, modifierFlags: [])
            app.typeKey(.downArrow, modifierFlags: [])

            // After two Down presses a different row should be highlighted.
            expectation(for: NSPredicate(format: "label != %@", firstLabel), evaluatedWith: selectedRow)
            waitForExpectations(timeout: 10)
        }

        /// Tracks cold-launch time, but `measure` re-runs the launch ~5 times — a cost
        /// nobody watches locally. It exists only to catch regressions in CI, so it's
        /// skipped unless `RUN_LAUNCH_PERF_TESTS` is set (the CI scheme sets it); local
        /// and PR runs no longer pay for it.
        @MainActor
        func testLaunchPerformance() throws {
            try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_LAUNCH_PERF_TESTS"] != nil,
                              "Set RUN_LAUNCH_PERF_TESTS to run launch-performance metrics.")
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
#endif
