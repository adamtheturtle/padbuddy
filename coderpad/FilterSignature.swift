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
