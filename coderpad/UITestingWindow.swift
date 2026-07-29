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

        /// Expands the main window to the screen's visible frame, or to a screenshot-specific
        /// size supplied after `-uiTestingWindowSize`, once. Re-sizing on every activation
        /// churns the layout and makes the screenshot test's clicks flaky; pinning `minSize`
        /// keeps a later SwiftUI layout pass from springing the window back mid-capture.
        static func sizeToScreenIfNeeded() {
            guard AccountsStore.isUITesting, !didSize, let screen = NSScreen.main else { return }

            let arguments = ProcessInfo.processInfo.arguments
            let requestedSize: NSSize? = {
                guard let flag = arguments.firstIndex(of: "-uiTestingWindowSize"),
                      arguments.indices.contains(flag + 1)
                else { return nil }
                let dimensions = arguments[flag + 1].split(separator: "x")
                guard dimensions.count == 2,
                      let width = Double(dimensions[0]),
                      let height = Double(dimensions[1]),
                      width > 0,
                      height > 0
                else { return nil }
                return NSSize(width: width, height: height)
            }()

            if requestedSize == nil,
               arguments.contains("-uiTestingKeepDefaultWindowSize") {
                didSize = true
                return
            }
            let target = requestedSize.map {
                NSRect(
                    x: screen.visibleFrame.midX - $0.width / 2,
                    y: screen.visibleFrame.midY - $0.height / 2,
                    width: $0.width,
                    height: $0.height
                )
            } ?? screen.visibleFrame
            for window in NSApp.windows where window.isVisible && window.styleMask.contains(.titled) {
                window.minSize = target.size
                window.setFrame(target, display: true)
            }
            didSize = true
        }
    }
#endif
