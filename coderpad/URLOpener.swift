//
//  URLOpener.swift
//  coderpad
//
//  A thin seam over opening a URL through the system, so the handful of
//  `NSWorkspace.shared.open` call sites go through one place instead of scattering
//  that incidental AppKit API across notifiers, services, and menu handlers. Like
//  the `Clipboard` seam, keeping it here is a step toward multi-platform
//  portability (#287): a future iOS/iPadOS build can swap the body for
//  `UIApplication.shared.open` (or the SwiftUI `openURL` action) without touching
//  any call site.
//

import AppKit

enum URLOpener {
    /// Open `url` through the system. External links launch the user's default
    /// handler; the app's own `coderpad://` scheme routes back through LaunchServices
    /// to deliver the deep link (and surface a window when none is open).
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
