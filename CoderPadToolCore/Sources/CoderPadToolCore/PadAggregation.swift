//
//  PadAggregation.swift
//  CoderPadToolCore
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

/// Folds the API's pad-state synonyms onto one canonical spelling, mirroring the app's
/// `PadState(apiState:)`: the Interview API reports a live pad as "started" while the
/// tool catalog (and the app UI) say "active", so comparing raw strings would make the
/// documented filter value unmatchable (#1014). Unknown states pass through lowercased.
public func canonicalPadState(_ raw: String) -> String {
    switch raw.lowercased() {
    case "started", "active", "running": "active"
    case "ended", "finished", "completed": "ended"
    case "pending", "draft": "pending"
    case let value: value
    }
}

/// Whether a pad passes the optional owner/state/language filters (case-insensitive
/// exact match; an empty/absent filter always passes). The state comparison folds API
/// synonyms first, so `state:"active"` matches pads the API reports as "started".
public func padMatches(_ pad: [String: Any], owner: String?, state: String?, language: String?) -> Bool {
    func equals(_ field: String, _ wanted: String?, normalize: (String) -> String = { $0.lowercased() }) -> Bool {
        guard let wanted, !wanted.isEmpty else { return true }

        return (pad[field] as? String).map(normalize) == normalize(wanted)
    }

    return equals("owner_email", owner)
        && equals("state", state, normalize: canonicalPadState)
        && equals("language", language)
}

/// The error message for a 2xx list response whose JSON object lacks the expected records
/// array: an API schema change or a 200-wrapped proxy/error page must be surfaced, never
/// silently counted as zero rows (#829, #830, #1024, #1026). The body is previewed rather
/// than echoed in full so an HTML error page doesn't flood the assistant.
public func invalidListResponseMessage(_ path: String, expecting key: String, body: String) -> String {
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    let preview = trimmed.count > 200 ? String(trimmed.prefix(200)) + "…" : trimmed
    return "The \(path) response wasn't the expected JSON object with a \"\(key)\" "
        + "array; the upstream server may have returned a proxy or error page. "
        + "Response begins: \(preview)"
}

/// The UTC calendar prefix (YYYY-MM or YYYY-MM-DD, per `count`) of an ISO-8601
/// `created_at`. Parsing and reformatting in UTC keeps month/date bucketing and
/// filtering identical no matter which offset the source spelled the instant in —
/// the API can send non-UTC offsets while the app's cache re-encodes to "Z", and the
/// two must never bucket the same record differently (#1034, #1035). An unparseable
/// value falls back to its raw prefix.
func utcCreatedPrefix(_ created: String, count: Int) -> String {
    guard let date = iso8601Date(from: created) else { return String(created.prefix(count)) }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return String(formatter.string(from: date).prefix(count))
}

/// Whether a record's `created_at` falls within an optional [after, before] range. Month
/// and date bounds are compared against the UTC-normalized prefix of `created_at`; full
/// ISO-8601 timestamps are parsed and compared as normalized instants. A record with no
/// `created_at` fails any present bound; empty/absent bounds always pass. Shared by the pad
/// and question count/aggregate tools.
public func withinDateRange(_ record: [String: Any], after: String?, before: String?) -> Bool {
    let created = (record["created_at"] as? String) ?? ""
    func passes(_ bound: String?, isAfter: Bool) -> Bool {
        guard let bound, !bound.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        guard !created.isEmpty else { return false }
        guard let dateBound = dateBound(from: bound) else { return false }

        switch dateBound {
        case let .month(value), let .day(value):
            let createdPrefix = utcCreatedPrefix(created, count: value.count)
            return isAfter ? createdPrefix >= value : createdPrefix <= value

        case let .timestamp(value):
            guard let createdDate = iso8601Date(from: created) else { return false }

            return isAfter ? createdDate >= value : createdDate <= value
        }
    }

    return passes(after, isAfter: true) && passes(before, isAfter: false)
}

/// Validates optional created_at bounds before a count/aggregate scan. Supported
/// forms intentionally match `withinDateRange`: month (`YYYY-MM`), date
/// (`YYYY-MM-DD`), or an ISO-8601 timestamp.
public func dateBoundValidationError(after: String?, before: String?) -> String? {
    if let error = dateBoundValidationError(name: "created_after", value: after) { return error }
    if let error = dateBoundValidationError(name: "created_before", value: before) { return error }
    return nil
}

private func dateBoundValidationError(name: String, value: String?) -> String? {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    guard isSupportedDateBound(value) else {
        return "\(name) must be a valid YYYY-MM month, YYYY-MM-DD date, or ISO-8601 timestamp."
    }

    return nil
}

public func isSupportedDateBound(_ value: String) -> Bool {
    dateBound(from: value) != nil
}

private enum DateBound {
    case month(String)
    case day(String)
    case timestamp(Date)
}

private func dateBound(from value: String) -> DateBound? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if isValidMonthBound(trimmed) { return .month(trimmed) }
    if isValidDateBound(trimmed) { return .day(trimmed) }
    if let date = iso8601Date(from: trimmed) { return .timestamp(date) }
    return nil
}

private func iso8601Date(from value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: value) { return date }

    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions.insert(.withFractionalSeconds)
    return fractionalFormatter.date(from: value)
}

private func isValidMonthBound(_ value: String) -> Bool {
    guard value.count == 7, value[value.index(value.startIndex, offsetBy: 4)] == "-",
          let month = Int(value.suffix(2)),
          value.prefix(4).allSatisfy(\.isNumber),
          (1 ... 12).contains(month)
    else { return false }

    return true
}

private func isValidDateBound(_ value: String) -> Bool {
    guard value.count == 10,
          value[value.index(value.startIndex, offsetBy: 4)] == "-",
          value[value.index(value.startIndex, offsetBy: 7)] == "-",
          value.prefix(4).allSatisfy(\.isNumber)
    else { return false }

    let parts = value.split(separator: "-")
    guard parts.count == 3,
          let year = Int(parts[0]),
          let month = Int(parts[1]),
          let day = Int(parts[2])
    else { return false }

    var calendar = Calendar(identifier: .gregorian)
    if let utc = TimeZone(secondsFromGMT: 0) {
        calendar.timeZone = utc
    }
    let components = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: year, month: month, day: day)
    guard let date = calendar.date(from: components) else { return false }

    let resolved = calendar.dateComponents([.year, .month, .day], from: date)
    return resolved.year == year && resolved.month == month && resolved.day == day
}

/// Adds active `created_after`/`created_before` bounds to a filters echo.
public func addDateFilters(_ filters: inout [String: Any], after: String?, before: String?) {
    if let after, !after.isEmpty { filters["created_after"] = after }
    if let before, !before.isEmpty { filters["created_before"] = before }
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
/// the first 7 chars of created_at (YYYY-MM); "state" buckets by the canonical state
/// spelling (so a group value can be fed straight back as a filter); missing/empty
/// values bucket as "unknown".
public func aggregateCounts(pads: [[String: Any]], field: String) -> [String: Int] {
    var counts: [String: Int] = [:]
    for pad in pads {
        let key: String
        if field == "month" {
            let created = (pad["created_at"] as? String) ?? ""
            key = created.count >= 7 ? utcCreatedPrefix(created, count: 7) : "unknown"
        } else {
            let raw = (pad[field] as? String).flatMap { $0.isEmpty ? nil : $0 }
            key = raw.map { field == "state" ? canonicalPadState($0) : $0 } ?? "unknown"
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
