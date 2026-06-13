//
//  WidgetSharedSnapshot.swift
//  RecentPadsWidget
//
//  The widget side of the data contract shared with the app. The app writes recent
//  pads into the App Group container (see the app's `WidgetPadSnapshot.swift` /
//  `WidgetSync.swift`); this reads them back. The two definitions are deliberately
//  kept in lock-step on the JSON shape (property names) rather than sharing a file,
//  so the widget target stays free of any app dependency.
//

import Foundation

/// A minimal, dependency-free projection of a pad for display in the widget.
struct WidgetPadSnapshot: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let language: String?
    let updatedAt: Date?
}

/// Reads the recent-pads snapshot from the App Group container shared with the app.
enum WidgetSharedStore {
    /// Must match the app's `WidgetSharedStore.appGroupID`. If `containerURL` ever
    /// returns nil at runtime, this likely needs the team-id prefixed form
    /// (`6L9H6Q8CUF.group.ptn.coderpad`) on macOS.
    static let appGroupID = "group.ptn.coderpad"

    /// The widget's kind, shared with the app's reload logic.
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
}
