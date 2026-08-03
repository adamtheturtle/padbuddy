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
        kindLabels = Dictionary(uniqueKeysWithValues: Set(events.map(\.kind)).map { ($0, Self.displayKind($0)) })
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
        return knownLabels[kind.lowercased()] ?? kind.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func actor(_ event: PadEvent) -> String? {
        if let name = event.userName, !name.isEmpty {
            return name
        }
        if let email = event.userEmail, !email.isEmpty {
            return email
        }
        return nil
    }
}
