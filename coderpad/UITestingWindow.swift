#if os(macOS)
//
    //  UITestingWindow.swift
    //  coderpad
//
    //  Test-only window sizing. When the app is driven by the seeded `-uiTesting` demo (for
    //  the UI tests and the marketing/App-Store screenshots), the main window is grown to fill
    //  the screen so a capture shows the full three-column layout rather than a cold-launch
    //  sliver. Gated on `-uiTesting`, so it never runs for real users.
//

    import AppKit

    enum UITestingWindow {
        private static var didSize = false

        /// Expands the main window to the screen's visible frame, once. Re-sizing on every
        /// activation churns the layout and makes the screenshot test's clicks flaky; pinning
        /// `minSize` keeps a later SwiftUI layout pass (a section switch, the command palette
        /// opening) from springing the window back to its content size mid-capture.
        static func sizeToScreenIfNeeded() {
            guard AccountsStore.isUITesting, !didSize, let screen = NSScreen.main else { return }

            let target = screen.visibleFrame
            for window in NSApp.windows where window.isVisible && window.styleMask.contains(.titled) {
                window.minSize = target.size
                window.setFrame(target, display: true)
            }
            didSize = true
        }
    }
#endif
