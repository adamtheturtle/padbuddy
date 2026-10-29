//
//  FilterSignature.swift
//  coderpad
//
//  Collision-free change tokens for live filter tuples.
//

import Foundation

struct FilterSignature: Hashable {
    /// Strings are copy-on-write values, so retaining canonical fields avoids copying
    /// long search text into a newly encoded token on every render while exact array
    /// equality remains collision-free.
    private let fields: [String?]

    static func make(_ fields: [String?]) -> Self {
        Self(fields: fields.map {
            $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
    }

    /// Exact identity for credentials and URLs, where case changes are meaningful.
    static func makeExact(_ fields: [String?]) -> Self {
        Self(fields: fields)
    }
}

/// Validation for the enum-like raw strings persisted in saved searches and
/// filter snapshots (#1651, #1652, #1653): a corrupt or stale value would
/// otherwise restore as an opaque active filter whose only possible result is
/// an empty list.
enum FilterValueValidation {
    /// `raw` when it names a known interview type (underscore spellings
    /// normalize, matching the pickers), else nil.
    static func interviewType(_ raw: String?) -> String? {
        guard let raw, InterviewType(rawType: raw) != nil else { return nil }

        return raw
    }

    /// `raw` when it is a known draft-state token, else nil — the draft
    /// predicate matches only these two literals, so anything else could never
    /// produce results (#1651).
    static func draftState(_ raw: String?) -> String? {
        raw == "draft" || raw == "published" ? raw : nil
    }
}

/// Canonical option lists shared by account and All Accounts filter bars.
enum FilterOptionValues {
    static func language(_ value: String?, matches selection: String?) -> Bool {
        guard let selection else { return true }

        return value?.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(selection.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    static func owner(_ value: String, matches selection: String?) -> Bool {
        selection.map { value.canonicalOwnerEmail == $0.canonicalOwnerEmail } ?? true
    }

    static let maximumOptions = 256

    static func boundedLanguages(_ values: some Sequence<String?>) -> [String] {
        boundedOptions(values, maximumBytes: 128, normalizedBytes: 128) {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    static func boundedOwners(_ values: some Sequence<String>) -> [String] {
        boundedOptions(values.lazy.map(Optional.some), maximumBytes: 512, normalizedBytes: 254) {
            $0.canonicalOwnerEmail
        }
    }

    static func boundedTeam(_ raw: String?) -> String? {
        guard let raw, raw.utf8.count <= 512, raw.unicodeScalars.count <= 128 else { return nil }

        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, isDisplaySafeIdentity(name) else { return nil }

        return name
    }

    static func boundedTeams(_ values: some Sequence<String?>) -> [String] {
        boundedOptions(values, maximumBytes: 512, normalizedBytes: 512) { boundedTeam($0) ?? "" }
    }

    private static func isDisplaySafeIdentity(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate, .unassigned: false
            default: true
            }
        }
    }

    private static func boundedOptions(
        _ values: some Sequence<String?>, maximumBytes: Int, normalizedBytes: Int,
        normalize: (String) -> String
    ) -> [String] {
        var options = Set<String>()
        for raw in values {
            guard let raw, raw.utf8.count <= maximumBytes else { continue }

            let value = normalize(raw)
            guard !value.isEmpty, value.utf8.count <= normalizedBytes,
                  isDisplaySafeIdentity(value) else { continue }

            options.insert(value)
            if options.count == maximumOptions {
                break
            }
        }
        return options.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func languages(_ values: some Sequence<String?>) -> [String] {
        Set(values.compactMap {
            $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        .filter { !$0.isEmpty }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func owners(_ values: some Sequence<String>) -> [String] {
        Set(values.map(\.canonicalOwnerEmail))
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
