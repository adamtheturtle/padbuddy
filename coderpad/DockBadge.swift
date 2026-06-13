//
//  DockBadge.swift
//  coderpad
//
//  Drives the count on the Dock icon. The badge reflects the number of *active*
//  (started) pads across every signed-in account — a live interview in progress
//  is the app's one genuinely time-sensitive signal, and unlike an "unread" count
//  it needs no read-tracking: it clears itself the moment a session ends. Gated by
//  a user preference (see `DockBadge.Key.showActivePads`), default on.
//

import AppKit

enum DockBadge {
    enum Key {
        /// Bool, default `true` (registered in `AppDelegate`). When off, the badge is
        /// cleared and never reapplied.
        static let showActivePads = "general.showActivePadsBadge"
    }

    /// Whether the badge is shown. Defaults to on; `AppDelegate` registers `true` for
    /// the unset case so this and the `@AppStorage` toggle agree before either is set.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.showActivePads)
    }

    /// Recompute the badge from the current pad caches and apply it on the main
    /// thread. Cheap and idempotent, so it's safe to call after any cache update,
    /// account change, or when the preference is toggled. Reading the cache and
    /// touching `NSApp.dockTile` both happen on the main actor.
    static func refresh() {
        Task { @MainActor in apply() }
    }

    /// Sum the active pads across all accounts and write the badge. An empty string
    /// (nil) removes the badge entirely, so "no active pads" shows a clean icon
    /// rather than a "0".
    @MainActor
    static func apply() {
        let count = PadsCacheStore.shared.padsByAccount.values
            .reduce(0) { running, pads in running + pads.filter { $0.status == .active }.count }
        NSApp.dockTile.badgeLabel = (isEnabled && count > 0) ? "\(count)" : nil
    }
}
