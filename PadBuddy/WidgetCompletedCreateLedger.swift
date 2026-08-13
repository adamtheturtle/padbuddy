//
//  WidgetCompletedCreateLedger.swift
//  PadBuddy
//

import Foundation

nonisolated enum WidgetCompletedCreateLedger {
    static let maximumEntries = 512
    private static let key = "widget.completed-new-pad-request-ids"

    static func shouldCreate(_ id: UUID, defaults: UserDefaults = .standard) -> Bool {
        !completedIDs(defaults: defaults).contains(id)
    }

    @discardableResult
    static func recordCompleted(_ id: UUID, defaults: UserDefaults = .standard) -> Bool {
        var ids = defaults.stringArray(forKey: key) ?? []
        let value = id.uuidString
        guard !ids.contains(value) else { return true }

        ids.append(value)
        if ids.count > maximumEntries {
            ids.removeFirst(ids.count - maximumEntries)
        }
        defaults.set(ids, forKey: key)
        return defaults.synchronize()
    }

    private static func completedIDs(defaults: UserDefaults) -> Set<UUID> {
        Set((defaults.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:)))
    }
}
