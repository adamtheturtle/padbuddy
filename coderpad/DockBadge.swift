//
//  DockBadge.swift
//  coderpad
//
//  Drives the count on the Dock icon. The user chooses what it counts (see
//  `DockBadge.Mode`): the active (started) pads across every account — a live
//  interview in progress — or the pads that have changed since they were last seen,
//  or nothing at all. Both counts are self-clearing, so neither needs read-tracking
//  beyond what the app already maintains.
//

import AppKit

enum DockBadge {
    /// What the Dock badge counts. Persisted as a raw string under `Key.mode`.
    enum Mode: String, CaseIterable, Identifiable {
        /// No badge.
        case off
        /// Started pads, summed across all accounts. The default.
        case activePads
        /// Pads whose activity advanced since the user last marked them seen, as
        /// tracked by `PadActivityMonitor` (the same count the menu-bar item shows).
        case unseenUpdates

        var id: String { rawValue }

        var label: String {
            switch self {
            case .off: "Off"
            case .activePads: "Active pads"
            case .unseenUpdates: "Pads with new activity"
            }
        }
    }

    enum Key {
        static let mode = "general.dockBadgeMode"
    }

    /// The chosen mode, defaulting to `.activePads` for the unset case — matching the
    /// `@AppStorage` default in Settings so the two never disagree.
    static var mode: Mode {
        Mode(rawValue: UserDefaults.standard.string(forKey: Key.mode) ?? "") ?? .activePads
    }

    /// Recompute the badge for the current mode and apply it on the main thread.
    /// Cheap and idempotent, so it's safe to call after any pad-cache change, when
    /// the unseen-activity count changes, or when the preference is edited. Reading
    /// the sources and touching `NSApp.dockTile` both happen on the main actor.
    static func refresh() {
        Task { @MainActor in apply() }
    }

    /// Resolve the count for the active mode and write the badge. An empty string
    /// (nil) removes the badge entirely, so "nothing to show" leaves a clean icon
    /// rather than a "0".
    @MainActor
    static func apply() {
        let count: Int
        switch mode {
        case .off:
            count = 0
        case .activePads:
            count = PadsCacheStore.shared.padsByAccount.values
                .reduce(0) { running, pads in running + pads.filter { $0.status == .active }.count }
        case .unseenUpdates:
            count = PadActivityMonitor.shared.unseenChangedCount
        }
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }
}
