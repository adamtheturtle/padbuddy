//
//  PadAggregation.swift
//  CoderPadMCPCore
//
//  The count / aggregate / compact transforms (#500). The executable pages the whole
//  pad list over the network; these pure functions do the filtering and tallying, so
//  "how many pads match X" returns a small answer instead of streaming every record
//  through the model.
//

import Foundation

/// Interprets a `next_page` value (a string token, or an int in some responses); nil
/// means there are no more pages.
public func nextPageToken(_ value: Any?) -> String? {
    switch value {
    case let token as String: token.isEmpty ? nil : token
    case let number as Int: String(number)
    default: nil
    }
}

/// Whether a pad passes the optional owner/state/language filters (case-insensitive
/// exact match; an empty/absent filter always passes).
public func padMatches(_ pad: [String: Any], owner: String?, state: String?, language: String?) -> Bool {
    func equals(_ field: String, _ wanted: String?) -> Bool {
        guard let wanted, !wanted.isEmpty else { return true }

        return (pad[field] as? String)?.lowercased() == wanted.lowercased()
    }

    return equals("owner_email", owner) && equals("state", state) && equals("language", language)
}

/// Echoes the active filters back into a result, for clarity on what was counted.
public func filtersEcho(owner: String?, state: String?, language: String?) -> [String: Any] {
    var filters: [String: Any] = [:]
    if let owner, !owner.isEmpty { filters["owner"] = owner }
    if let state, !state.isEmpty { filters["state"] = state }
    if let language, !language.isEmpty { filters["language"] = language }
    return filters
}

/// Normalizes a user-facing `group_by` to a pad field, or nil when unsupported. The
/// special value "month" buckets by the year-month of created_at.
public func aggregateField(for groupBy: String) -> String? {
    switch groupBy.lowercased() {
    case "owner", "owner_email": "owner_email"
    case "language": "language"
    case "state": "state"
    case "month", "created_at": "month"
    default: nil
    }
}

/// Tallies pads into { groupKey: count } for a normalized field. "month" buckets by
/// the first 7 chars of created_at (YYYY-MM); missing/empty values bucket as
/// "unknown".
public func aggregateCounts(pads: [[String: Any]], field: String) -> [String: Int] {
    var counts: [String: Int] = [:]
    for pad in pads {
        let key: String
        if field == "month" {
            let created = (pad["created_at"] as? String) ?? ""
            key = created.count >= 7 ? String(created.prefix(7)) : "unknown"
        } else {
            key = (pad[field] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
        }
        counts[key, default: 0] += 1
    }
    return counts
}

/// A single aggregation bucket: the group value and its count.
public struct AggregateGroup: Equatable {
    public let value: String
    public let count: Int

    public init(value: String, count: Int) {
        self.value = value
        self.count = count
    }
}

/// Sorts counts by count descending, then key ascending (deterministic), and caps to
/// `limit` groups.
public func topGroups(_ counts: [String: Int], limit: Int) -> [AggregateGroup] {
    let sorted = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
    return sorted.prefix(limit).map { AggregateGroup(value: $0.key, count: $0.value) }
}

/// The fields kept by list_pads_compact, dropping the verbose blob so far more rows
/// fit per response.
public let compactPadKeys = ["id", "title", "owner_email", "state", "language", "created_at"]

/// Projects pads down to the compact key set.
public func compactPads(_ pads: [[String: Any]]) -> [[String: Any]] {
    pads.map { pad in
        var row: [String: Any] = [:]
        for key in compactPadKeys where pad[key] != nil {
            row[key] = pad[key]
        }
        return row
    }
}
