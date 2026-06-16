//
//  CoderPadAPI+Requests.swift
//  coderpad
//
//  Encode-only request bodies for the pad and question mutation endpoints.
//

import Foundation

struct PadUpdate: Codable {
    var id: String
    var title: String?
    var language: String?
    var ownerEmail: String?
    var notes: String?
    var isPrivate: Bool?
    var executionEnabled: Bool?
    /// Resets the pad's editor contents. The API warns this destroys the pad's
    /// history, so callers should confirm before sending. Mutually exclusive with
    /// `questionID` — sending both is rejected by the API.
    var contents: String?
    /// Associates a question with the pad, mirroring "create from question" on the
    /// web. Mutually exclusive with `contents`.
    var questionID: Int?
    /// Set to `true` to end the interview. Any other value is ignored by the API.
    var ended: Bool?
    /// Set to `true` to delete the interview. Any other value is ignored by the API.
    var deleted: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, language, notes, contents, ended, deleted
        case ownerEmail = "owner_email"
        case isPrivate = "private"
        case executionEnabled = "execution_enabled"
        case questionID = "question_id"
    }
}

/// Request body for creating a question. `title` and `language` are encoded nested
/// under a `question` object to match the API's documented `question[title]` /
/// `question[language]` parameters; the remaining fields are sent flat, as the API
/// documents them. Encode-only — these are never decoded.
struct QuestionCreate: Encodable {
    var title: String
    var language: String?
    var description: String?
    var solution: String?
    /// Starter code inserted into the interview session when this question is used.
    var contents: String?
    var takeHome: Bool?
    var padType: String?
    var candidateInstructions: [CandidateInstructionPayload]?

    private enum CodingKeys: String, CodingKey {
        case description, solution, contents, question
        case takeHome = "take_home"
        case padType = "pad_type"
        case candidateInstructions = "candidate_instructions"
    }

    private enum QuestionKeys: String, CodingKey {
        case title, language
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(solution, forKey: .solution)
        try container.encodeIfPresent(contents, forKey: .contents)
        try container.encodeIfPresent(takeHome, forKey: .takeHome)
        try container.encodeIfPresent(padType, forKey: .padType)
        try container.encodeIfPresent(candidateInstructions, forKey: .candidateInstructions)
        var question = container.nestedContainer(keyedBy: QuestionKeys.self, forKey: .question)
        try question.encode(title, forKey: .title)
        try question.encodeIfPresent(language, forKey: .language)
    }
}

/// Request body for modifying a question. Like `QuestionCreate`, `title`/`language`
/// are nested under `question`. The `id` travels in the URL path; it is also encoded
/// flat here for parity with the create payload. Encode-only.
struct QuestionUpdate: Encodable {
    var id: Int
    var title: String?
    var language: String?
    var description: String?
    var solution: String?
    /// Starter code inserted into the interview session when this question is used.
    var contents: String?
    var takeHome: Bool?
    var padType: String?
    var candidateInstructions: [CandidateInstructionPayload]?

    private enum CodingKeys: String, CodingKey {
        case id, description, solution, contents, question
        case takeHome = "take_home"
        case padType = "pad_type"
        case candidateInstructions = "candidate_instructions"
    }

    private enum QuestionKeys: String, CodingKey {
        case title, language
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(solution, forKey: .solution)
        try container.encodeIfPresent(contents, forKey: .contents)
        try container.encodeIfPresent(takeHome, forKey: .takeHome)
        try container.encodeIfPresent(padType, forKey: .padType)
        try container.encodeIfPresent(candidateInstructions, forKey: .candidateInstructions)
        if title != nil || language != nil {
            var question = container.nestedContainer(keyedBy: QuestionKeys.self, forKey: .question)
            try question.encodeIfPresent(title, forKey: .title)
            try question.encodeIfPresent(language, forKey: .language)
        }
    }
}

struct CandidateInstructionPayload: Codable {
    var instructions: String
    var defaultVisible: Bool

    enum CodingKeys: String, CodingKey {
        case instructions
        case defaultVisible = "default_visible"
    }
}

nonisolated struct PadCreate: Codable {
    var title: String?
    var language: String?
    var ownerEmail: String?
    var contents: String?
    var notes: String?
    var isPrivate: Bool?
    var executionEnabled: Bool?
    /// Question to seed the pad from. The API documents this as singular
    /// `question_id` on create (the plural `question_ids` is a response-only field).
    /// Mutually exclusive with `contents`.
    var questionID: Int?
    /// Links the new pad to a specific team. Settable only by org owners; omit to
    /// use the account's default team.
    var teamID: String?

    enum CodingKeys: String, CodingKey {
        case title, language, contents, notes
        case ownerEmail = "owner_email"
        case isPrivate = "private"
        case executionEnabled = "execution_enabled"
        case questionID = "question_id"
        case teamID = "team_id"
    }

    /// A pad seeded from a question: same title and language, with the question attached.
    static func fromQuestion(_ question: Question) -> PadCreate {
        PadCreate(
            title: question.title,
            language: question.language,
            ownerEmail: nil,
            contents: nil,
            notes: nil,
            isPrivate: false,
            executionEnabled: true,
            questionID: question.id
        )
    }
}

// MARK: - execution_enabled string quirk

/// Encodes the optional execution flag the way CoderPad's pad endpoints actually
/// expect it: as the JSON **string** `"true"`/`"false"`, not a JSON boolean.
///
/// This contradicts the published API docs, which document `execution_enabled` as a
/// boolean. A real boolean is accepted by the request but silently ignored — the pad
/// falls back to the account default, so a new pad comes back execution-disabled even
/// when `true` was sent. Sending the string form is what actually takes effect. See
/// issue #305. `nil` is omitted entirely.
private nonisolated func encodeExecutionEnabled<K: CodingKey>(
    _ value: Bool?,
    into container: inout KeyedEncodingContainer<K>,
    forKey key: K
) throws {
    try container.encodeIfPresent(value.map { $0 ? "true" : "false" }, forKey: key)
}

/// Decodes `execution_enabled` tolerantly, accepting either the string form we now
/// send or a plain boolean (older payloads / the published-docs shape).
private nonisolated func decodeExecutionEnabled<K: CodingKey>(
    from container: KeyedDecodingContainer<K>,
    forKey key: K
) throws -> Bool? {
    if let string = try? container.decode(String.self, forKey: key) { return string == "true" }
    return try container.decodeIfPresent(Bool.self, forKey: key)
}

extension PadCreate {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        ownerEmail = try container.decodeIfPresent(String.self, forKey: .ownerEmail)
        contents = try container.decodeIfPresent(String.self, forKey: .contents)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate)
        executionEnabled = try decodeExecutionEnabled(from: container, forKey: .executionEnabled)
        questionID = try container.decodeIfPresent(Int.self, forKey: .questionID)
        teamID = try container.decodeIfPresent(String.self, forKey: .teamID)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(ownerEmail, forKey: .ownerEmail)
        try container.encodeIfPresent(contents, forKey: .contents)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(isPrivate, forKey: .isPrivate)
        try encodeExecutionEnabled(executionEnabled, into: &container, forKey: .executionEnabled)
        try container.encodeIfPresent(questionID, forKey: .questionID)
        try container.encodeIfPresent(teamID, forKey: .teamID)
    }
}

extension PadUpdate {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        ownerEmail = try container.decodeIfPresent(String.self, forKey: .ownerEmail)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate)
        executionEnabled = try decodeExecutionEnabled(from: container, forKey: .executionEnabled)
        contents = try container.decodeIfPresent(String.self, forKey: .contents)
        questionID = try container.decodeIfPresent(Int.self, forKey: .questionID)
        ended = try container.decodeIfPresent(Bool.self, forKey: .ended)
        deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(ownerEmail, forKey: .ownerEmail)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(isPrivate, forKey: .isPrivate)
        try encodeExecutionEnabled(executionEnabled, into: &container, forKey: .executionEnabled)
        try container.encodeIfPresent(contents, forKey: .contents)
        try container.encodeIfPresent(questionID, forKey: .questionID)
        try container.encodeIfPresent(ended, forKey: .ended)
        try container.encodeIfPresent(deleted, forKey: .deleted)
    }
}
