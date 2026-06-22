//
//  QuestionAggregation.swift
//  CoderPadMCPCore
//
//  The count / aggregate / compact transforms for the QUESTION bank (#500), mirroring
//  PadAggregation. The executable pages the whole question list over the network; these
//  pure functions filter and tally, so "how many questions by language / author" returns a
//  small answer instead of streaming every record through the model. Questions expose
//  owner_email, author_name, language, pad_type and created_at, so they group and filter by
//  those (rather than pads' owner/state/language). The field-agnostic helpers —
//  aggregateCounts, topGroups, nextPageToken — are reused from PadAggregation.
//

import Foundation

/// Whether a question passes the optional owner/author/language/type filters
/// (case-insensitive exact match; an empty/absent filter always passes).
public func questionMatches(
    _ question: [String: Any], owner: String?, author: String?, language: String?, type: String?
) -> Bool {
    func equals(_ field: String, _ wanted: String?) -> Bool {
        guard let wanted, !wanted.isEmpty else { return true }

        return (question[field] as? String)?.lowercased() == wanted.lowercased()
    }

    return equals("owner_email", owner) && equals("author_name", author)
        && equals("language", language) && equals("pad_type", type)
}

/// Echoes the active question filters back into a result, for clarity on what was counted.
public func questionFiltersEcho(owner: String?, author: String?, language: String?, type: String?) -> [String: Any] {
    var filters: [String: Any] = [:]
    if let owner, !owner.isEmpty { filters["owner"] = owner }
    if let author, !author.isEmpty { filters["author"] = author }
    if let language, !language.isEmpty { filters["language"] = language }
    if let type, !type.isEmpty { filters["type"] = type }
    return filters
}

/// Normalizes a user-facing `group_by` to a question field, or nil when unsupported. The
/// special value "month" buckets by the year-month of created_at.
public func questionAggregateField(for groupBy: String) -> String? {
    switch groupBy.lowercased() {
    case "owner", "owner_email": "owner_email"
    case "author", "author_name": "author_name"
    case "language": "language"
    case "type", "pad_type": "pad_type"
    case "month", "created_at": "month"
    default: nil
    }
}

/// The fields kept by list_questions_compact, dropping the verbose blob (description,
/// solution, starter code, test cases) so far more rows fit per response.
public let compactQuestionKeys = [
    "id", "title", "owner_email", "author_name", "language", "pad_type", "is_draft", "created_at"
]

/// Projects questions down to the compact key set.
public func compactQuestions(_ questions: [[String: Any]]) -> [[String: Any]] {
    questions.map { question in
        var row: [String: Any] = [:]
        for key in compactQuestionKeys where question[key] != nil {
            row[key] = question[key]
        }
        return row
    }
}
