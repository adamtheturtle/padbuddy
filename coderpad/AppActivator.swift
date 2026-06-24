//
//  AppActivator.swift
//  coderpad
//
//  A thin seam over bringing the app to the foreground, so the `NSApp.activate`
//  calls that pair with a deep-link open (notification taps, the Services provider,
//  the Dock menu) go through one place. Like the `Clipboard` and `URLOpener` seams,
//  it keeps an incidental AppKit API behind a single helper toward multi-platform
//  portability (#287): there's no iOS equivalent of an app activating itself, so a
//  future iOS build can make this a no-op without touching the call sites.
//

#if os(macOS)
    import AppKit
#endif

enum AppActivator {
    /// Bring the app to the foreground, e.g. before delivering a deep link so the
    /// activated window comes forward with it. A no-op on iOS, where an app cannot
    /// activate itself — exactly as this seam was designed to allow.
    static func bringToFront() {
        #if os(macOS)
            NSApp.activate(ignoringOtherApps: true)
        #endif
    }
}
