//
//  WidgetPadSnapshot.swift
//  coderpad
//
//  The data contract shared between the app and its widget extension. This file
//  must be a member of BOTH the `coderpad` app target (which writes snapshots) and
//  the `coderpadWidget` extension target (which reads them) — add the widget target
//  membership in the File inspector. It deliberately depends on nothing but
//  Foundation so it compiles cleanly in the lean widget process.
//
//  A widget runs in its own sandbox and cannot read the app's private cache, so the
//  app mirrors a small slice of the current account's recent pads into a shared App
//  Group container and the widget reads it back.
//

import Foundation

/// A minimal, dependency-free projection of a `Pad` for display in the widget.
nonisolated struct WidgetPadSnapshot: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let language: String?
    let updatedAt: Date?
}

/// Reads and writes the recent-pads snapshot in the App Group container shared by
/// the app and the widget. All members are `nonisolated` so the widget's timeline
/// provider can call them off the main actor.
nonisolated enum WidgetSharedStore {
    /// Shared container identifier. Declared in both targets' entitlements. If
    /// `containerURL` ever returns nil at runtime, this likely needs the team-id
    /// prefixed form (`6L9H6Q8CUF.group.ptn.coderpad`) on macOS.
    static let appGroupID = "group.ptn.coderpad"

    /// The widget's kind, shared so the app and widget agree on the identifier.
    static let widgetKind = "RecentPadsWidget"

    private static let fileName = "recent-pads.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appending(path: fileName, directoryHint: .notDirectory)
    }

    /// The last snapshot the app wrote, or an empty list when none exists yet.
    static func load() -> [WidgetPadSnapshot] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([WidgetPadSnapshot].self, from: data)) ?? []
    }

    /// Atomically replaces the snapshot. A no-op when the shared container is
    /// unavailable, so callers needn't guard the entitlement themselves.
    static func save(_ pads: [WidgetPadSnapshot]) {
        guard let fileURL, let data = try? JSONEncoder().encode(pads) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
