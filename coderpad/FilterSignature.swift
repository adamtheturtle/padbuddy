//
//  FilterSignature.swift
//  coderpad
//
//  Collision-free change tokens for live filter tuples.
//

enum FilterSignature {
    static func make(_ fields: [String?]) -> String {
        fields.map(token).joined()
    }

    private static func token(_ field: String?) -> String {
        guard let field else { return "n;" }

        return "s\(field.utf8.count):\(field);"
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
