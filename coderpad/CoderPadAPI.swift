//
//  CoderPadAPI.swift
//  coderpad
//

import Foundation
import os.log

nonisolated let apiLogger = Logger(subsystem: "com.coderpad.app", category: "api")

extension KeyedDecodingContainer {
    /// Like `try? decodeIfPresent`, but logs the underlying error so silent API drift
    /// shows up in Console rather than producing an empty UI with no diagnostic.
    nonisolated func loggedDecodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        do {
            return try decodeIfPresent(type, forKey: key)
        } catch {
            apiLogger.debug("decodeIfPresent '\(key.stringValue, privacy: .public)' as \(String(describing: type), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

// MARK: - Models

nonisolated struct Pad: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let state: String
    let ownerEmail: String
    let language: String?
    let participants: [String]
    let url: String
    let playback: String?
    /// API URL for this pad's event log. Convenience field; `padEvents(padID:)`
    /// derives the same URL from `id`, so this is decoded only for fidelity.
    let events: String?
    /// Private interviewer notes. Round-trips with `PadCreate`/`PadUpdate`.
    let notes: String?
    /// URL of the pad's whiteboard drawing image, if any.
    let drawing: String?
    /// Pad code contents (legacy single-file representation).
    let contents: String?
    /// Firebase history URL for the pad.
    let history: String?
    let createdAt: Date?
    let updatedAt: Date?
    let endedAt: Date?
    let type: String?
    let executionEnabled: Bool?
    let isPrivate: Bool?
    let activeEnvironmentID: Int?
    let padEnvironmentIDs: [Int]
    let questionIDs: [Int]
    let team: PadTeam?

    enum CodingKeys: String, CodingKey {
        case id, title, state, language, participants, url, playback, type, team
        case notes, drawing, contents, history, events
        case ownerEmail = "owner_email"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case endedAt = "ended_at"
        case executionEnabled = "execution_enabled"
        case isPrivate = "private"
        case activeEnvironmentID = "active_environment_id"
        case padEnvironmentIDs = "pad_environment_ids"
        case questionIDs = "question_ids"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = c.loggedDecodeIfPresent(String.self, forKey: .title) ?? ""
        state = c.loggedDecodeIfPresent(String.self, forKey: .state) ?? "unknown"
        ownerEmail = c.loggedDecodeIfPresent(String.self, forKey: .ownerEmail) ?? ""
        language = c.loggedDecodeIfPresent(String.self, forKey: .language)
        // The live API can include `null` entries in `participants` (e.g. an
        // anonymous or not-yet-named guest), so decode as optional strings and
        // drop the nulls rather than letting one null fail the whole array.
        participants = (c.loggedDecodeIfPresent([String?].self, forKey: .participants) ?? []).compactMap { $0 }
        url = c.loggedDecodeIfPresent(String.self, forKey: .url) ?? ""
        playback = c.loggedDecodeIfPresent(String.self, forKey: .playback)
        events = c.loggedDecodeIfPresent(String.self, forKey: .events)
        notes = c.loggedDecodeIfPresent(String.self, forKey: .notes)
        drawing = c.loggedDecodeIfPresent(String.self, forKey: .drawing)
        contents = c.loggedDecodeIfPresent(String.self, forKey: .contents)
        history = c.loggedDecodeIfPresent(String.self, forKey: .history)
        createdAt = c.loggedDecodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = c.loggedDecodeIfPresent(Date.self, forKey: .updatedAt)
        endedAt = c.loggedDecodeIfPresent(Date.self, forKey: .endedAt)
        type = c.loggedDecodeIfPresent(String.self, forKey: .type)
        executionEnabled = c.loggedDecodeIfPresent(Bool.self, forKey: .executionEnabled)
        isPrivate = c.loggedDecodeIfPresent(Bool.self, forKey: .isPrivate)
        activeEnvironmentID = c.loggedDecodeIfPresent(Int.self, forKey: .activeEnvironmentID)
        padEnvironmentIDs = c.loggedDecodeIfPresent([Int].self, forKey: .padEnvironmentIDs) ?? []
        questionIDs = c.loggedDecodeIfPresent([Int].self, forKey: .questionIDs) ?? []
        team = c.loggedDecodeIfPresent(PadTeam.self, forKey: .team)
    }
}

extension Pad {
    /// The `updatedAt` timestamp, but only when it carries information beyond the
    /// pad's end time. Ending a pad is itself a write, so for ended pads
    /// `updated_at` usually equals `ended_at` and surfacing both is redundant.
    /// Show it only when a later edit (notes, feedback) moved `updated_at`
    /// meaningfully past the end.
    var informativeUpdatedAt: Date? {
        guard let updatedAt else { return nil }
        guard let endedAt else { return updatedAt }
        return updatedAt.timeIntervalSince(endedAt) > 60 ? updatedAt : nil
    }
}

nonisolated struct PadTeam: Codable, Hashable {
    let id: String
    let name: String
}

nonisolated struct PadEvent: Decodable, Identifiable, Hashable {
    var id: String { "\(createdAt?.timeIntervalSince1970 ?? 0)-\(kind)-\(userName ?? "")-\(message)" }
    let message: String
    let kind: String
    /// Event-specific context: the language run for `ran`, the question ID for
    /// `added_question`, "spectator" for a spectator `joined`, etc.
    let metadata: String?
    let userName: String?
    let userEmail: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case message, kind, metadata
        case userName = "user_name"
        case userEmail = "user_email"
        case createdAt = "created_at"
    }
}

/// One file within a pad environment. Single-file languages return one of these;
/// multi-file frameworks/projects return one per file in the project.
nonisolated struct PadEnvironmentFile: Decodable, Hashable {
    let path: String?
    let contents: String?
    let history: String?
}

nonisolated struct PadEnvironment: Decodable, Identifiable, Hashable {
    let id: Int
    let padID: Int?
    let questionID: Int?
    /// e.g. "examples/035-django-shopping-list" when seeded from a CoderPad example.
    let exampleQuestionID: String?
    let language: String?
    let fileContents: [PadEnvironmentFile]
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, language
        case padID = "pad_id"
        case questionID = "question_id"
        case exampleQuestionID = "example_question_id"
        case fileContents = "file_contents"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        padID = c.loggedDecodeIfPresent(Int.self, forKey: .padID)
        questionID = c.loggedDecodeIfPresent(Int.self, forKey: .questionID)
        exampleQuestionID = c.loggedDecodeIfPresent(String.self, forKey: .exampleQuestionID)
        language = c.loggedDecodeIfPresent(String.self, forKey: .language)
        fileContents = c.loggedDecodeIfPresent([PadEnvironmentFile].self, forKey: .fileContents) ?? []
        createdAt = c.loggedDecodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = c.loggedDecodeIfPresent(Date.self, forKey: .updatedAt)
    }

    /// The combined code across all files in the environment, for a simple preview.
    /// Multi-file projects are concatenated with a header per file path.
    var contents: String? {
        let files = fileContents.compactMap { file -> String? in
            guard let body = file.contents, !body.isEmpty else { return nil }
            if fileContents.count > 1, let path = file.path, !path.isEmpty {
                return "// \(path)\n\(body)"
            }
            return body
        }
        return files.isEmpty ? nil : files.joined(separator: "\n\n")
    }
}

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
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(solution, forKey: .solution)
        try c.encodeIfPresent(contents, forKey: .contents)
        try c.encodeIfPresent(takeHome, forKey: .takeHome)
        try c.encodeIfPresent(padType, forKey: .padType)
        try c.encodeIfPresent(candidateInstructions, forKey: .candidateInstructions)
        var q = c.nestedContainer(keyedBy: QuestionKeys.self, forKey: .question)
        try q.encode(title, forKey: .title)
        try q.encodeIfPresent(language, forKey: .language)
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
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(solution, forKey: .solution)
        try c.encodeIfPresent(contents, forKey: .contents)
        try c.encodeIfPresent(takeHome, forKey: .takeHome)
        try c.encodeIfPresent(padType, forKey: .padType)
        try c.encodeIfPresent(candidateInstructions, forKey: .candidateInstructions)
        if title != nil || language != nil {
            var q = c.nestedContainer(keyedBy: QuestionKeys.self, forKey: .question)
            try q.encodeIfPresent(title, forKey: .title)
            try q.encodeIfPresent(language, forKey: .language)
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
    static func fromQuestion(_ q: Question) -> PadCreate {
        PadCreate(
            title: q.title,
            language: q.language,
            ownerEmail: nil,
            contents: nil,
            notes: nil,
            isPrivate: false,
            executionEnabled: true,
            questionID: q.id
        )
    }
}

nonisolated struct Question: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let ownerEmail: String
    let language: String?
    let description: String?
    let shared: Bool?
    let used: Int?
    let takeHome: Bool?
    let testCasesEnabled: Bool?
    let solution: String?
    let padType: String?
    let isDraft: Bool?
    let authorName: String?
    let organizationName: String?
    /// Starter code inserted into the pad when this question is used.
    let contents: String?
    /// Starter code variant used when the question runs against test cases.
    let contentsForTestCases: String?
    let publicTakeHomeSettingID: Int?
    let customFiles: [QuestionCustomFile]
    let testCases: [QuestionTestCase]
    let createdAt: Date?
    let updatedAt: Date?
    let candidateInstructions: [CandidateInstruction]

    enum CodingKeys: String, CodingKey {
        case id, title, language, description, shared, used, solution, contents
        case ownerEmail = "owner_email"
        case takeHome = "take_home"
        case testCasesEnabled = "test_cases_enabled"
        case padType = "pad_type"
        case isDraft = "is_draft"
        case authorName = "author_name"
        case organizationName = "organization_name"
        case contentsForTestCases = "contents_for_test_cases"
        case publicTakeHomeSettingID = "public_take_home_setting_id"
        case customFiles = "custom_files"
        case testCases = "test_cases"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case candidateInstructions = "candidate_instructions"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = c.loggedDecodeIfPresent(String.self, forKey: .title) ?? ""
        ownerEmail = c.loggedDecodeIfPresent(String.self, forKey: .ownerEmail) ?? ""
        language = c.loggedDecodeIfPresent(String.self, forKey: .language)
        description = c.loggedDecodeIfPresent(String.self, forKey: .description)
        shared = c.loggedDecodeIfPresent(Bool.self, forKey: .shared)
        used = c.loggedDecodeIfPresent(Int.self, forKey: .used)
        takeHome = c.loggedDecodeIfPresent(Bool.self, forKey: .takeHome)
        testCasesEnabled = c.loggedDecodeIfPresent(Bool.self, forKey: .testCasesEnabled)
        solution = c.loggedDecodeIfPresent(String.self, forKey: .solution)
        padType = c.loggedDecodeIfPresent(String.self, forKey: .padType)
        isDraft = c.loggedDecodeIfPresent(Bool.self, forKey: .isDraft)
        authorName = c.loggedDecodeIfPresent(String.self, forKey: .authorName)
        organizationName = c.loggedDecodeIfPresent(String.self, forKey: .organizationName)
        contents = c.loggedDecodeIfPresent(String.self, forKey: .contents)
        contentsForTestCases = c.loggedDecodeIfPresent(String.self, forKey: .contentsForTestCases)
        publicTakeHomeSettingID = c.loggedDecodeIfPresent(Int.self, forKey: .publicTakeHomeSettingID)
        customFiles = c.loggedDecodeIfPresent([QuestionCustomFile].self, forKey: .customFiles) ?? []
        testCases = c.loggedDecodeIfPresent([QuestionTestCase].self, forKey: .testCases) ?? []
        createdAt = c.loggedDecodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = c.loggedDecodeIfPresent(Date.self, forKey: .updatedAt)
        candidateInstructions = c.loggedDecodeIfPresent([CandidateInstruction].self, forKey: .candidateInstructions) ?? []
    }
}

/// Whether a pad or question is a real-time **live** interview or an async
/// **take-home**. CoderPad models this inconsistently across resources: pads
/// expose a free-form `type` string, while questions expose a `take_home`
/// boolean (and, on newer records, a `pad_type` string). `InterviewType`
/// normalizes all of these so the UI can present one consistent "Type" control.
enum InterviewType: String, CaseIterable, Identifiable, Hashable {
    case live
    case takeHome = "take-home"

    var id: String { rawValue }

    /// Human-facing label for filter menus and badges.
    var label: String {
        switch self {
        case .live: "Live"
        case .takeHome: "Take-home"
        }
    }

    /// Normalize a raw pad `type` / `pad_type` string. Accepts the hyphen and
    /// underscore spellings the API has used. Returns `nil` for empty or
    /// unrecognized values so callers can decide how to treat unexpected data.
    init?(rawType: String?) {
        switch rawType?.lowercased() {
        case "live": self = .live
        case "take-home", "take_home", "takehome": self = .takeHome
        default: return nil
        }
    }
}

/// A pad's lifecycle state, normalized from the API's free-form `state` string.
/// CoderPad reports states like "started"/"ended"/"pending"; older or future
/// records may use synonyms ("active", "finished", "draft"). `PadState` folds the
/// known spellings into typed cases and preserves anything unrecognized as
/// `.other`, so the UI can switch over states without scattering string literals.
/// Like ``InterviewType`` it round-trips through a stable lowercase `rawValue`,
/// which keeps saved-search persistence wire-compatible with snapshots that stored
/// the raw state string.
enum PadState: Hashable, Identifiable, Codable, RawRepresentable {
    case active
    case ended
    case pending
    case deleted
    /// A state the app doesn't model explicitly; carries the raw API spelling so it
    /// still renders and round-trips.
    case other(String)

    /// Normalize a raw API `state` string, folding known synonyms into typed cases.
    init(apiState raw: String) {
        switch raw.lowercased() {
        case "started", "active", "live", "running": self = .active
        case "ended", "finished", "completed": self = .ended
        case "pending", "draft": self = .pending
        case "deleted": self = .deleted
        case let value: self = .other(value)
        }
    }

    /// Total over all strings — unrecognized values become `.other` rather than
    /// failing — so it also serves as the `Codable`/saved-search decode path.
    init?(rawValue: String) { self.init(apiState: rawValue) }

    /// Canonical lowercase spelling, used for persistence and filter identity.
    var rawValue: String {
        switch self {
        case .active: "active"
        case .ended: "ended"
        case .pending: "pending"
        case .deleted: "deleted"
        case .other(let raw): raw
        }
    }

    var id: String { rawValue }

    /// Whether this is a terminal state.
    var isEnded: Bool { self == .ended }

    /// Human-facing label for badges and filter menus.
    var label: String {
        switch self {
        case .active: "Active"
        case .ended: "Ended"
        case .pending: "Pending"
        case .deleted: "Deleted"
        case .other(let raw): raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    init(from decoder: Decoder) throws {
        self.init(apiState: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

extension Pad {
    /// Live vs take-home, normalized from the API's free-form `type` string.
    /// `nil` when the pad reports no (or an unrecognized) type.
    var interviewType: InterviewType? { InterviewType(rawType: type) }

    /// The pad's lifecycle state, normalized from the free-form `state` string.
    var status: PadState { PadState(apiState: state) }

    /// Whether the interview has finished. Prefers the explicit `ended_at`
    /// timestamp, falling back to the reported state.
    var isEnded: Bool { endedAt != nil || status == .ended }

    /// The pad's web URL, parsed from the API's `url` string.
    var webURL: URL? { URL(string: url) }

    /// The session playback URL, when the pad has one.
    var playbackURL: URL? { playback.flatMap(URL.init(string:)) }
}

extension Question {
    /// Live vs take-home. Prefers the `pad_type` string when present, otherwise
    /// derives it from the `take_home` boolean — defaulting to `.live`, which is
    /// how the API treats an absent or false `take_home`.
    var interviewType: InterviewType {
        InterviewType(rawType: padType) ?? (takeHome == true ? .takeHome : .live)
    }
}

nonisolated struct QuestionCustomFile: Codable, Hashable, Identifiable {
    let id: String?
    let title: String?
    let description: String?
    let filename: String?
    let filesize: String?
}

nonisolated struct QuestionTestCase: Codable, Hashable, Identifiable {
    let id: Int
    let returnValue: String?
    let visible: Bool?
    let arguments: [String]?

    enum CodingKeys: String, CodingKey {
        case id, visible, arguments
        case returnValue = "return_value"
    }
}

nonisolated struct CandidateInstruction: Codable, Hashable {
    let instructions: String
    let defaultVisible: Bool

    enum CodingKeys: String, CodingKey {
        case instructions
        case defaultVisible = "default_visible"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        instructions = (try? c.decodeIfPresent(String.self, forKey: .instructions)) ?? ""
        defaultVisible = (try? c.decodeIfPresent(Bool.self, forKey: .defaultVisible)) ?? true
    }
}

nonisolated struct Organization: Decodable, Hashable {
    let id: Int
    let organizationName: String
    let userCount: Int?
    let users: [OrganizationUser]
    let teams: [PadTeam]
    let organizationDefaultLanguage: String?
    let singleSignOnSupported: Bool?
    /// URL of the organization's SSO sign-in portal, when SSO is supported.
    let singleSignInURL: String?

    enum CodingKeys: String, CodingKey {
        case id, users, teams
        case organizationName = "organization_name"
        case userCount = "user_count"
        case organizationDefaultLanguage = "organization_default_language"
        case singleSignOnSupported = "single_sign_on_supported"
        case singleSignInURL = "single_sign_in_url"
    }
}

nonisolated struct OrganizationUser: Decodable, Identifiable, Hashable {
    var id: String { email }
    let email: String
    let name: String?
    let teams: [String]?
    let padsCreated: Int?

    enum CodingKeys: String, CodingKey {
        case email, name, teams
        case padsCreated = "pads_created"
    }
}

nonisolated struct OrganizationStats: Decodable, Hashable {
    let startTime: Date?
    let endTime: Date?
    let padsCreated: Int
    let users: [OrganizationUser]

    enum CodingKeys: String, CodingKey {
        case users
        case startTime = "start_time"
        case endTime = "end_time"
        case padsCreated = "pads_created"
    }
}

nonisolated struct Quota: Decodable, Hashable {
    let trialExpiresAt: Date?
    let padsUsed: Int?
    let quotaReset: Date?
    let unlimited: Bool?
    let overagesEnabled: Bool?
    /// Pads left in the current billing cycle. Absent (nil) when `unlimited` is true.
    let padsRemaining: Int?
    /// Total pads allocated for the billing cycle. Absent (nil) when `unlimited` is true.
    let billingCyclePadLimit: Int?

    enum CodingKeys: String, CodingKey {
        case unlimited
        case trialExpiresAt = "trial_expires_at"
        case padsUsed = "pads_used"
        case quotaReset = "quota_reset_at"
        case overagesEnabled = "overages_enabled"
        case padsRemaining = "pads_remaining"
        case billingCyclePadLimit = "billing_cycle_pad_limit"
    }
}

// MARK: - Pagination

/// A list response that may span multiple pages. The API returns at most 50 items
/// per page, plus an absolute `next_page` URL when more remain. Callers that ignore
/// it silently see only the first page.
///
/// `total` (the count across all pages, when the endpoint reports it) lets the client
/// compute the page count from the first response and fetch the rest concurrently,
/// rather than walking `next_page` one blocking round-trip at a time.
private protocol PagedResponse: Decodable, Sendable {
    associatedtype Item: Decodable & Sendable
    // `nonisolated` so the pagination pipeline can read these off the main actor
    // (see `streamAllPages`); without it the module's default MainActor isolation
    // would make the protocol requirements main-actor-isolated.
    nonisolated var pageItems: [Item] { get }
    nonisolated var nextPage: String? { get }
    nonisolated var total: Int? { get }
}

private nonisolated struct PadsPage: PagedResponse {
    let pads: [Pad]
    let nextPage: String?
    let total: Int?
    var pageItems: [Pad] { pads }
    enum CodingKeys: String, CodingKey { case pads; case nextPage = "next_page"; case total }
}

private nonisolated struct QuestionsPage: PagedResponse {
    let questions: [Question]
    let nextPage: String?
    let total: Int?
    var pageItems: [Question] { questions }
    enum CodingKeys: String, CodingKey { case questions; case nextPage = "next_page"; case total }
}

private nonisolated struct EventsPage: PagedResponse {
    let events: [PadEvent]
    let nextPage: String?
    let total: Int?
    var pageItems: [PadEvent] { events }
    enum CodingKeys: String, CodingKey { case events; case nextPage = "next_page"; case total }
}

// MARK: - Errors

enum CoderPadError: LocalizedError {
    case missingAPIKey
    case http(Int, String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing API key. Open Settings to add an account."
        case .http(let code, let body):
            return Self.message(forStatus: code, body: body)
        case .decode(let detail):
            return "Couldn't read response: \(detail)"
        }
    }

    /// A human-facing sentence for an HTTP failure. Deliberately never echoes the raw
    /// response body — surfacing `{"status":404,"error":"Not Found"}` in an alert leaks
    /// the transport layer into the UI. Known status codes get a plain-language
    /// explanation; for anything else we prefer a message the API itself supplied,
    /// falling back to a generic line that keeps the code for a bug report.
    private static func message(forStatus code: Int, body: String) -> String {
        switch code {
        case 401, 403:
            return "You're not authorized. Check this account's API key in Settings."
        case 404:
            return "The server couldn't find that. It may have already been deleted."
        case 429:
            return "CoderPad is rate-limiting requests right now. Try again in a moment."
        case 500...599:
            return "CoderPad had a server error. Please try again shortly."
        default:
            if let apiMessage = apiMessage(from: body) { return apiMessage }
            return "The request failed (HTTP \(code))."
        }
    }

    /// Pulls a human-readable message out of an error response body, if it carries one.
    /// CoderPad returns errors as `{"message": …}` or `{"error": …}`; we ignore the bare
    /// `status`/`error` boilerplate (e.g. "Not Found") so only a real explanation shows.
    private static func apiMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        for key in ["message", "error_description", "error"] {
            if let value = object[key] as? String,
               !value.isEmpty,
               value.caseInsensitiveCompare("Not Found") != .orderedSame {
                return value
            }
        }
        return nil
    }

    var isUnauthorized: Bool {
        if case .http(401, _) = self { return true }
        if case .http(403, _) = self { return true }
        return false
    }
}

// MARK: - Response envelopes

// Small decode-only response shapes shared across endpoints. `nonisolated` so they're
// Sendable and can be decoded off the main actor (see `CoderPadClient.perform`).
private nonisolated struct StatusOnly: Decodable { let status: String? }
private nonisolated struct Empty: Decodable {}
private nonisolated struct Wrapper: Decodable { let users: [OrganizationUser] }

// MARK: - Client

struct CoderPadClient {
    // The client carries only immutable, Sendable configuration and drives pure
    // networking, so these are `nonisolated`: it lets the low-level request/
    // pagination methods below run off the main actor (see `streamAllPages`)
    // rather than being pinned to it by the module's default MainActor isolation.
    nonisolated let apiKey: String
    nonisolated let baseURL: URL
    nonisolated let session: URLSession

    /// The standard hosted CoderPad endpoint, used when an account doesn't
    /// override it (e.g. a self-hosted or regional deployment).
    static let defaultBaseURL = URL(string: "https://app.coderpad.io")!

    init(apiKey: String,
         baseURL: URL = CoderPadClient.defaultBaseURL,
         session: URLSession = CoderPadClient.liveSession) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
    }

    /// The single construction point for the live network session, so request
    /// policy (timeouts, caching) lives here rather than relying on the
    /// process-wide `URLSession.shared` singleton. Tests inject
    /// `MockServer.session(_:)` instead (see `mock(_:)`), so both
    /// session-construction strategies are owned by this type.
    static let liveSession: URLSession = makeLiveSession()

    private static func makeLiveSession() -> URLSession {
        let config = URLSessionConfiguration.default
        // The retry layer (`performWithRetry`) handles transient timeouts, so keep
        // the standard 60s per-request timeout rather than failing fast.
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config)
    }

    static func live(apiKey: String, baseURL: URL = CoderPadClient.defaultBaseURL) -> CoderPadClient {
        CoderPadClient(apiKey: apiKey, baseURL: baseURL, session: liveSession)
    }

    /// `unauthorized: true` returns a client whose mock server answers 401 for every
    /// request, backing the "bad key" demo account.
    static func mock(unauthorized: Bool = false) -> CoderPadClient {
        CoderPadClient(apiKey: "demo", session: MockServer.session(unauthorized: unauthorized))
    }

    // The API mixes fractional- and whole-second ISO-8601 timestamps, so we try both.
    // `ISO8601DateFormatter` is thread-safe for parsing and these are configured once
    // and only ever read, so sharing them across the off-main decodes is safe — the
    // `unsafe` vouches for that, since the type isn't formally `Sendable`.
    nonisolated(unsafe) private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let basicDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Builds a configured decoder. A factory rather than a shared instance because
    /// decoding runs off the main actor (see `perform`), and `JSONDecoder` isn't safe
    /// to share across threads — each background decode gets its own.
    nonisolated static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = fractionalDateFormatter.date(from: s) ?? basicDateFormatter.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrecognized date: \(s)")
        }
        return d
    }

    /// Shared decoder for callers that decode on the current actor (e.g. tests).
    /// The network path decodes off-main via `makeDecoder()` instead.
    static let decoder: JSONDecoder = makeDecoder()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // MARK: Pads

    /// `sort` accepts e.g. "updated_at,desc" or "created_at,asc". Defaults to the
    /// API's `created_at,desc`. All pages are followed, not just the first 50.
    func listPads(sort: String? = nil) async throws -> [Pad] {
        try await fetchAllPages(PadsPage.self, path: "/api/pads/", sort: sort)
    }

    /// Streams pads for progressive display. The first element arrives after a single
    /// round-trip (page 1), so the UI can render immediately; each subsequent element is
    /// a larger cumulative snapshot as more pages land, and the last element is the
    /// complete list. With the default `updated_at,desc` sort, page 1 is already the top
    /// of the final list, so rows only ever append below — no reshuffle mid-load.
    func listPadsIncrementally(sort: String? = "updated_at,desc") -> AsyncThrowingStream<[Pad], Error> {
        streamAllPages(PadsPage.self, path: "/api/pads/", sort: sort)
    }

    func getPad(id: String) async throws -> Pad {
        // The live API returns the pad's fields flat at the top level (alongside
        // "status"), not nested under a "pad" key.
        try await fetch(Pad.self, path: "/api/pads/\(id)")
    }

    func padEvents(padID: String) async throws -> [PadEvent] {
        try await fetchAllPages(EventsPage.self, path: "/api/pads/\(padID)/events")
    }

    func padEnvironment(id: Int) async throws -> PadEnvironment {
        // The live API returns the environment's fields flat at the top level.
        try await fetch(PadEnvironment.self, path: "/api/pad_environments/\(id)")
    }

    func createPad(_ body: PadCreate) async throws -> Pad {
        // Single-resource pad endpoints (this POST and GET /api/pads/:id) return the
        // pad's fields flat at the top level, alongside "status".
        return try await send(Pad.self, method: "POST", path: "/api/pads/", body: body)
    }

    /// The live API replies `{"status":"OK"}` with no pad body, so we re-fetch the
    /// pad to return its fresh server state rather than decoding the (absent) body.
    /// The pad id travels in the URL path (`PUT /api/pads/:id`) per the API's
    /// "Modify a pad" contract — not just in the body.
    func updatePad(_ body: PadUpdate) async throws -> Pad {
        _ = try await send(StatusOnly.self, method: "PUT", path: "/api/pads/\(body.id)", body: body)
        return try await getPad(id: body.id)
    }

    /// Ends the interview, by setting `ended` on the pad. The live API replies
    /// `{"status":"OK"}` with no pad body.
    func endPad(id: String) async throws {
        _ = try await send(StatusOnly.self, method: "PUT", path: "/api/pads/\(id)",
                           body: PadUpdate(id: id, ended: true))
    }

    /// Deletes the pad. CoderPad has no `DELETE` for pads; deletion is the same
    /// "Modify a pad" endpoint with `deleted` set — `PUT /api/pads/:id` with the id
    /// in the URL path. The live API replies `{"status":"OK"}`.
    func deletePad(id: String) async throws {
        _ = try await send(StatusOnly.self, method: "PUT", path: "/api/pads/\(id)",
                           body: PadUpdate(id: id, deleted: true))
    }

    // MARK: Questions

    func listQuestions(sort: String? = nil) async throws -> [Question] {
        try await fetchAllPages(QuestionsPage.self, path: "/api/questions/", sort: sort)
    }

    /// Streams questions for progressive display, like `listPadsIncrementally`: page 1
    /// arrives after a single round-trip, then larger cumulative snapshots until the full
    /// list is in. With `updated_at,desc` the first page is already the top of the list.
    func listQuestionsIncrementally(sort: String? = "updated_at,desc") -> AsyncThrowingStream<[Question], Error> {
        streamAllPages(QuestionsPage.self, path: "/api/questions/", sort: sort)
    }

    func getQuestion(id: Int) async throws -> Question {
        // The live API returns the question's fields flat at the top level (alongside
        // "status"), not nested under a "question" key.
        try await fetch(Question.self, path: "/api/questions/\(id)")
    }

    func createQuestion(_ body: QuestionCreate) async throws -> Question {
        // Single-resource question endpoints (this POST and GET /api/questions/:id)
        // return the question's fields flat at the top level, alongside "status".
        return try await send(Question.self, method: "POST", path: "/api/questions/", body: body)
    }

    /// The live API replies `{"status":"OK"}` with no question body, so we re-fetch the
    /// question to return its fresh server state rather than decoding the (absent) body.
    func updateQuestion(_ body: QuestionUpdate) async throws -> Question {
        _ = try await send(StatusOnly.self, method: "PUT", path: "/api/questions/\(body.id)", body: body)
        return try await getQuestion(id: body.id)
    }

    func deleteQuestion(id: Int) async throws {
        var request = URLRequest(url: baseURL.appending(path:"/api/questions/\(id)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        _ = try await perform(Empty.self, request: request)
    }

    // MARK: Quota / Organization

    func quota() async throws -> Quota {
        return try await fetch(Quota.self, path: "/api/quota")
    }

    func organization() async throws -> Organization {
        return try await fetch(Organization.self, path: "/api/organization")
    }

    /// Pad usage stats for the organization. With no range the API reports the
    /// last 7 days; passing `start`/`end` configures the window (both are required
    /// together, per the API contract).
    func organizationStats(start: Date? = nil, end: Date? = nil) async throws -> OrganizationStats {
        guard !apiKey.isEmpty else { throw CoderPadError.missingAPIKey }
        var comps = URLComponents(url: baseURL.appending(path:"/api/organization/stats"),
                                  resolvingAgainstBaseURL: false)
        if let start, let end {
            comps?.queryItems = [
                URLQueryItem(name: "start_time", value: start.formatted(.iso8601)),
                URLQueryItem(name: "end_time", value: end.formatted(.iso8601)),
            ]
        }
        guard let url = comps?.url else { throw CoderPadError.http(0, "Invalid URL") }
        return try await performWithRetry(OrganizationStats.self, request: authorizedGET(url))
    }

    /// Every pad in the organization (requires org-owner access or org-wide visibility),
    /// rather than just the API key owner's pads. Paginated like `listPads`.
    func listOrganizationPads(sort: String? = nil) async throws -> [Pad] {
        try await fetchAllPages(PadsPage.self, path: "/api/organization/pads", sort: sort)
    }

    /// Every organization question visible to you. Paginated like `listQuestions`.
    func listOrganizationQuestions(sort: String? = nil) async throws -> [Question] {
        try await fetchAllPages(QuestionsPage.self, path: "/api/organization/questions", sort: sort)
    }

    /// The organization's users. Passing `email` returns only the matching user — the
    /// reliable way to resolve which user an API key belongs to.
    func organizationUsers(email: String? = nil) async throws -> [OrganizationUser] {
        guard !apiKey.isEmpty else { throw CoderPadError.missingAPIKey }
        var comps = URLComponents(url: baseURL.appending(path:"/api/organization/users"),
                                  resolvingAgainstBaseURL: false)
        if let email { comps?.queryItems = [URLQueryItem(name: "email", value: email)] }
        guard let url = comps?.url else { throw CoderPadError.http(0, "Invalid URL") }
        return try await performWithRetry(Wrapper.self, request: authorizedGET(url)).users
    }

    // MARK: Plumbing

    nonisolated private func authorizedGET(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func fetch<T: Decodable & Sendable>(_ type: T.Type, path: String) async throws -> T {
        guard !apiKey.isEmpty else { throw CoderPadError.missingAPIKey }
        return try await performWithRetry(type, request: authorizedGET(baseURL.appending(path:path)))
    }

    /// Accumulates every page of a paginated list endpoint. Convenience over
    /// `streamAllPages` for callers that only want the final, complete list.
    private func fetchAllPages<W: PagedResponse>(_ type: W.Type, path: String, sort: String? = nil) async throws -> [W.Item] {
        var items: [W.Item] = []
        for try await snapshot in streamAllPages(W.self, path: path, sort: sort) { items = snapshot }
        return items
    }

    /// Streams cumulative snapshots of a paginated list endpoint, yielding page 1 first so
    /// callers can render before the whole list is in.
    ///
    /// When the first response reports a `total`, the page count is known up front and the
    /// remaining pages (numbered `?page=2…N`) are fetched concurrently — turning what was a
    /// serial chain of round-trips into a few parallel waves. On a real account with ~2,000
    /// pads this is the difference between ~40s and a few seconds. Completed pages are
    /// emitted as a growing contiguous prefix, so each snapshot is correctly ordered even
    /// though pages finish out of order. Endpoints that omit `total` (or any future
    /// cursor-style pagination) fall back to walking `next_page` sequentially, emitting a
    /// snapshot per page. Without this whole mechanism, callers would silently receive only
    /// the first 50 records.
    nonisolated private func streamAllPages<W: PagedResponse>(_ type: W.Type, path: String, sort: String? = nil) -> AsyncThrowingStream<[W.Item], Error> {
        AsyncThrowingStream { continuation in
            // This method and the networking it calls are `nonisolated`, so this
            // unstructured `Task` does not inherit the module's default main-actor
            // isolation — the pipeline, including the concurrent child tasks below,
            // runs on the cooperative pool. That keeps the list-building work (URL
            // construction, snapshot accumulation) off the main thread while pages
            // stream in. (Inheriting the main actor is exactly what a plain `Task`
            // would do from a MainActor-isolated context, regardless of Sendability.)
            let work = Task {
                do {
                    guard !apiKey.isEmpty else { throw CoderPadError.missingAPIKey }
                    let baseQuery: [URLQueryItem] = sort.map { [URLQueryItem(name: "sort", value: $0)] } ?? []

                    // Builds `…/path?sort=…&page=N`. Page numbers are constructed here
                    // rather than taken from `next_page` so the parallel fetch is
                    // fully deterministic.
                    func pageURL(_ page: Int?) -> URL? {
                        var comps = URLComponents(url: baseURL.appending(path:path), resolvingAgainstBaseURL: false)
                        var query = baseQuery
                        if let page { query.append(URLQueryItem(name: "page", value: String(page))) }
                        comps?.queryItems = query.isEmpty ? nil : query
                        return comps?.url
                    }

                    guard let firstURL = pageURL(nil) else { throw CoderPadError.http(0, "Invalid URL") }
                    let firstPage = try await performWithRetry(W.self, request: authorizedGET(firstURL))
                    var items = firstPage.pageItems
                    continuation.yield(items)

                    // Fast path: total + page-number URLs let us fetch pages 2…N in parallel.
                    if let total = firstPage.total, !items.isEmpty {
                        let pageSize = items.count
                        // `total` is a lower bound on the page count: it can undercount
                        // if records are created mid-load, and the first page can be
                        // short. So fetch pages 2…N in parallel, then follow `next_page`
                        // from the final page to pick up any remainder rather than
                        // silently dropping records past the estimate.
                        let pageCount = max(1, (total + pageSize - 1) / pageSize)
                        var tailNextPage: String? = firstPage.nextPage

                        if pageCount > 1 {
                            var pending: [Int: W] = [:]
                            var nextToEmit = 2
                            try await withThrowingTaskGroup(of: (Int, W).self) { group in
                                func enqueue(_ page: Int) throws {
                                    guard let url = pageURL(page) else { throw CoderPadError.http(0, "Invalid URL") }
                                    group.addTask {
                                        (page, try await self.performWithRetry(W.self, request: self.authorizedGET(url)))
                                    }
                                }
                                // Keep a bounded window in flight — enough to saturate the
                                // network without unleashing dozens of connections (which
                                // invite 429s).
                                let maxConcurrent = 8
                                var nextToFetch = 2
                                while nextToFetch <= pageCount, nextToFetch - 2 < maxConcurrent {
                                    try enqueue(nextToFetch); nextToFetch += 1
                                }
                                while let (page, response) = try await group.next() {
                                    pending[page] = response
                                    // The final page's `next_page` tells us whether the
                                    // estimate fell short.
                                    if page == pageCount { tailNextPage = response.nextPage }
                                    // Emit a new snapshot whenever the contiguous prefix grows.
                                    var grew = false
                                    while let ready = pending.removeValue(forKey: nextToEmit) {
                                        items.append(contentsOf: ready.pageItems); nextToEmit += 1; grew = true
                                    }
                                    if grew { continuation.yield(items) }
                                    if nextToFetch <= pageCount { try enqueue(nextToFetch); nextToFetch += 1 }
                                }
                            }
                        }

                        // Walk any pages beyond the estimated count sequentially.
                        var url = tailNextPage.flatMap { URL(string: $0) }
                        var pages = pageCount
                        while let current = url {
                            let page = try await performWithRetry(W.self, request: authorizedGET(current))
                            items.append(contentsOf: page.pageItems)
                            continuation.yield(items)
                            pages += 1
                            // Safety valve against a server that keeps handing back next_page links.
                            guard pages < 1000, let next = page.nextPage, let nextURL = URL(string: next) else { break }
                            url = nextURL
                        }
                        continuation.finish()
                        return
                    }

                    // Fallback: follow `next_page` one page at a time.
                    var url = firstPage.nextPage.flatMap { URL(string: $0) }
                    var pages = 1
                    while let current = url {
                        let page = try await performWithRetry(W.self, request: authorizedGET(current))
                        items.append(contentsOf: page.pageItems)
                        continuation.yield(items)
                        pages += 1
                        // Safety valve against a server that keeps handing back next_page links.
                        guard pages < 1000, let next = page.nextPage, let nextURL = URL(string: next) else { break }
                        url = nextURL
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    /// GET requests are idempotent, so transient failures (5xx, 429, network timeouts)
    /// are retried with exponential backoff before the error surfaces to the UI. Mutating
    /// requests go straight through `perform` to avoid duplicating side effects.
    nonisolated private func performWithRetry<T: Decodable & Sendable>(_ type: T.Type, request: URLRequest, maxAttempts: Int = 3) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await perform(type, request: request)
            } catch {
                attempt += 1
                guard attempt < maxAttempts, Self.isTransient(error) else { throw error }
                apiLogger.debug("Transient failure on \(request.url?.path ?? "", privacy: .public); retry \(attempt)/\(maxAttempts - 1)")
                // 300ms, then 600ms
                try? await Task.sleep(for: .milliseconds(300 * (1 << (attempt - 1))))
            }
        }
    }

    nonisolated private static func isTransient(_ error: Error) -> Bool {
        if let api = error as? CoderPadError, case .http(let code, _) = api {
            return (500...599).contains(code) || code == 429 || code == 0
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return [NSURLErrorTimedOut,
                    NSURLErrorNetworkConnectionLost,
                    NSURLErrorCannotConnectToHost].contains(ns.code)
        }
        return false
    }

    private func send<T: Decodable & Sendable, B: Encodable>(_ type: T.Type, method: String, path: String, body: B) async throws -> T {
        guard !apiKey.isEmpty else { throw CoderPadError.missingAPIKey }
        var request = URLRequest(url: baseURL.appending(path:path))
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder.encode(body)
        return try await perform(type, request: request)
    }

    nonisolated private func perform<T: Decodable & Sendable>(_ type: T.Type, request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CoderPadError.http(0, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CoderPadError.http(http.statusCode, body)
        }
        do {
            // Decode off the main actor: the client is MainActor-isolated, so on a large
            // account (~40 pages × 50 nested objects) decoding here would hitch the UI.
            // `Data` and `T` are Sendable, so the work crosses the boundary cleanly.
            return try await Self.decodeInBackground(T.self, from: data)
        } catch let DecodingError.keyNotFound(key, ctx) {
            throw CoderPadError.decode("missing key '\(key.stringValue)' at \(pathString(ctx.codingPath))")
        } catch let DecodingError.valueNotFound(type, ctx) {
            throw CoderPadError.decode("missing value of \(type) at \(pathString(ctx.codingPath))")
        } catch let DecodingError.typeMismatch(type, ctx) {
            throw CoderPadError.decode("type mismatch (\(type)) at \(pathString(ctx.codingPath)): \(ctx.debugDescription)")
        } catch let DecodingError.dataCorrupted(ctx) {
            throw CoderPadError.decode("corrupted at \(pathString(ctx.codingPath)): \(ctx.debugDescription)")
        }
    }

    nonisolated private func pathString(_ keys: [CodingKey]) -> String {
        keys.map { $0.stringValue }.joined(separator: ".")
    }

    /// Decodes `data` on a background task so the (potentially large) parse doesn't run on
    /// the main actor. Builds a fresh decoder per call — `JSONDecoder` isn't safe to share
    /// across threads. `DecodingError`s propagate so `perform` can map them as before.
    nonisolated private static func decodeInBackground<T: Decodable & Sendable>(_ type: T.Type, from data: Data) async throws -> T {
        try await Task.detached(priority: .userInitiated) {
            try makeDecoder().decode(T.self, from: data)
        }.value
    }
}
