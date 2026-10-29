//
//  PadEventPresentationCache.swift
//  coderpad
//

import Foundation

/// One memoized presentation pass for the Events pane.
final class PadEventPresentationCache {
    struct Key: Equatable {
        let revision: Int
    }

    private(set) var key: Key?
    private(set) var kindLabels: [String: String] = [:]
    private(set) var groups: [PadEventGroup] = []
    private(set) var activeParticipant: String?

    func refresh(events: [PadEvent], revision: Int) {
        let key = Key(revision: revision)
        guard self.key != key else { return }

        self.key = key
        let kinds = Set(events.map { PadEventKind.normalized($0.kind) })
        kindLabels = Dictionary(uniqueKeysWithValues: kinds.map { ($0, Self.displayKind($0)) })
        groups = PadEventGrouping.group(events)
        activeParticipant = groups.reversed().lazy.compactMap {
            Self.actor($0.lastEvent) ?? Self.actor($0.representative)
        }.first
    }

    static func displayKind(_ kind: String) -> String {
        let knownLabels = [
            "joined": String(localized: "Joined"),
            "left": String(localized: "Left"),
            "ended": String(localized: "Ended"),
            "started": String(localized: "Started"),
            "edited": String(localized: "Edited"),
            "typed": String(localized: "Typed"),
            "typed_code": String(localized: "Typed Code"),
            "ran": String(localized: "Ran"),
            "executed": String(localized: "Executed"),
            "added_question": String(localized: "Added Question")
        ]
        let key = PadEventKind.normalized(kind)
        if let known = knownLabels[key] {
            return known
        }
        let label = ExternalText.singleLine(key.replacingOccurrences(of: "_", with: " ").capitalized, limit: 64)
        return label.isEmpty ? String(localized: "Unknown") : label
    }

    static func actor(_ event: PadEvent) -> String? {
        let name = ExternalText.singleLine(event.userName ?? "", limit: 120)
        if !name.isEmpty {
            return name
        }
        let email = ExternalText.singleLine(event.userEmail ?? "", limit: 254)
        return email.isEmpty ? nil : email
    }
}
