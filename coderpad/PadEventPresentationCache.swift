//
//  PadEventPresentationCache.swift
//  coderpad
//

import Foundation

/// One memoized presentation pass for the Events pane.
final class PadEventPresentationCache {
    struct Key: Equatable {
        let revision: Int
        let participant: String?
        let kind: String?
    }

    private(set) var key: Key?
    private(set) var participants: [String] = []
    private(set) var kinds: [String] = []
    private(set) var kindLabels: [String: String] = [:]
    private(set) var filtered: [PadEvent] = []
    private(set) var groups: [PadEventGroup] = []
    private(set) var activeParticipant: String?

    func refresh(events: [PadEvent], revision: Int, filter: PadEventFilterState) {
        let key = Key(revision: revision, participant: filter.participant, kind: filter.kind)
        guard self.key != key else { return }

        self.key = key
        let labels = Dictionary(uniqueKeysWithValues: Set(events.map(\.kind)).map { ($0, Self.displayKind($0)) })
        kindLabels = labels
        kinds = labels.keys.sorted {
            let comparison = labels[$0, default: $0].localizedCaseInsensitiveCompare(labels[$1, default: $1])
            return comparison == .orderedAscending
        }
        participants = Set(events.compactMap(Self.actor))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        filtered = events.filter { event in
            (filter.participant == nil || Self.actor(event) == filter.participant)
                && (filter.kind == nil || event.kind == filter.kind)
        }
        groups = PadEventGrouping.group(filtered)
        activeParticipant = groups.reversed().lazy.compactMap {
            Self.actor($0.lastEvent) ?? Self.actor($0.representative)
        }.first
    }

    static func displayKind(_ kind: String) -> String {
        kind.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func actor(_ event: PadEvent) -> String? {
        if let name = event.userName, !name.isEmpty { return name }
        if let email = event.userEmail, !email.isEmpty { return email }
        return nil
    }
}
