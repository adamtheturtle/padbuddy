//
//  WidgetSync.swift
//  coderpad
//
//  Bridges the app's pad data to the Recent Pads widget. The widget lives in its
//  own sandbox, so it can't read the app's cache directly; instead the app mirrors
//  a small slice of the current account's recent pads into the shared App Group
//  container (see `WidgetSharedStore`) and asks WidgetKit to refresh.
//

import Foundation
import WidgetKit

enum WidgetSync {
    /// How many pads the widget ever needs, even at its largest size.
    private static let maxPads = 8

    /// Mirrors the most recently updated pads into the shared container and reloads
    /// the widget. Cheap and idempotent, so it's safe to call on every cache update
    /// and account switch. A no-op when the App Group container is unavailable.
    static func refresh(pads: [Pad]) {
        WidgetSharedStore.save(recentSnapshots(from: pads))
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func recentSnapshots(from pads: [Pad]) -> [WidgetPadSnapshot] {
        pads
            .sorted { lhs, rhs in
                (lhs.updatedAt ?? lhs.createdAt ?? .distantPast)
                    > (rhs.updatedAt ?? rhs.createdAt ?? .distantPast)
            }
            .prefix(maxPads)
            .map { pad in
                WidgetPadSnapshot(
                    id: pad.id,
                    title: pad.title.isEmpty ? "Untitled pad" : pad.title,
                    subtitle: pad.ownerEmail,
                    language: pad.language,
                    updatedAt: pad.updatedAt ?? pad.createdAt
                )
            }
    }
}
