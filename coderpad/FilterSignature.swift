//
//  FilterSignature.swift
//  coderpad
//
//  Collision-free change tokens for live filter tuples.
//

enum FilterSignature {
    /// Folded straight into one string rather than building an intermediate array of
    /// per-field tokens. These are change tokens compared in `onChange` and derived
    /// state, so they are made often and thrown away immediately — the array and every
    /// per-field String it held were pure garbage (#2256).
    static func make(_ fields: [String?]) -> String {
        fields.reduce(into: "") { signature, field in
            guard let field else {
                signature += "n;"
                return
            }

            signature += "s"
            signature += String(field.utf8.count)
            signature += ":"
            signature += field
            signature += ";"
        }
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
