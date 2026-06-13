//
//  CoderPadAPI+Questions.swift
//  coderpad
//
//  The `Question` model, the normalized `InterviewType` / `PadState` value types,
//  and the supporting question sub-models plus the `Pad`/`Question` convenience
//  extensions that depend on them.
//

import Foundation

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
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = container.loggedDecodeIfPresent(String.self, forKey: .title) ?? ""
        ownerEmail = container.loggedDecodeIfPresent(String.self, forKey: .ownerEmail) ?? ""
        language = container.loggedDecodeIfPresent(String.self, forKey: .language)
        description = container.loggedDecodeIfPresent(String.self, forKey: .description)
        shared = container.loggedDecodeIfPresent(Bool.self, forKey: .shared)
        used = container.loggedDecodeIfPresent(Int.self, forKey: .used)
        takeHome = container.loggedDecodeIfPresent(Bool.self, forKey: .takeHome)
        testCasesEnabled = container.loggedDecodeIfPresent(Bool.self, forKey: .testCasesEnabled)
        solution = container.loggedDecodeIfPresent(String.self, forKey: .solution)
        padType = container.loggedDecodeIfPresent(String.self, forKey: .padType)
        isDraft = container.loggedDecodeIfPresent(Bool.self, forKey: .isDraft)
        authorName = container.loggedDecodeIfPresent(String.self, forKey: .authorName)
        organizationName = container.loggedDecodeIfPresent(String.self, forKey: .organizationName)
        contents = container.loggedDecodeIfPresent(String.self, forKey: .contents)
        contentsForTestCases = container.loggedDecodeIfPresent(String.self, forKey: .contentsForTestCases)
        publicTakeHomeSettingID = container.loggedDecodeIfPresent(Int.self, forKey: .publicTakeHomeSettingID)
        customFiles = container.loggedDecodeIfPresent([QuestionCustomFile].self, forKey: .customFiles) ?? []
        testCases = container.loggedDecodeIfPresent([QuestionTestCase].self, forKey: .testCases) ?? []
        createdAt = container.loggedDecodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = container.loggedDecodeIfPresent(Date.self, forKey: .updatedAt)
        candidateInstructions = container
            .loggedDecodeIfPresent([CandidateInstruction].self, forKey: .candidateInstructions) ?? []
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

    var id: String {
        rawValue
    }

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
    init?(rawValue: String) {
        self.init(apiState: rawValue)
    }

    /// Canonical lowercase spelling, used for persistence and filter identity.
    var rawValue: String {
        switch self {
        case .active: "active"
        case .ended: "ended"
        case .pending: "pending"
        case .deleted: "deleted"
        case let .other(raw): raw
        }
    }

    var id: String {
        rawValue
    }

    /// Whether this is a terminal state.
    var isEnded: Bool {
        self == .ended
    }

    /// Human-facing label for badges and filter menus.
    var label: String {
        switch self {
        case .active: "Active"
        case .ended: "Ended"
        case .pending: "Pending"
        case .deleted: "Deleted"
        case let .other(raw): raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// SF Symbol paired with this state when it's rendered as restrained
    /// metadata (every state except the prominent "Active"; see ``StateBadge``).
    var systemImage: String {
        switch self {
        case .active: "dot.radiowaves.left.and.right"
        case .ended: "checkmark.circle"
        case .pending: "clock"
        case .deleted: "trash"
        case .other: "circle"
        }
    }

    init(from decoder: Decoder) throws {
        try self.init(apiState: decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension Pad {
    /// Live vs take-home, normalized from the API's free-form `type` string.
    /// `nil` when the pad reports no (or an unrecognized) type.
    var interviewType: InterviewType? {
        InterviewType(rawType: type)
    }

    /// The pad's lifecycle state, normalized from the free-form `state` string.
    var status: PadState {
        PadState(apiState: state)
    }

    /// Whether the interview has finished. Prefers the explicit `ended_at`
    /// timestamp, falling back to the reported state.
    var isEnded: Bool {
        endedAt != nil || status == .ended
    }

    /// The pad's web URL, parsed from the API's `url` string.
    var webURL: URL? {
        URL(string: url)
    }

    /// The session playback URL, when the pad has one.
    var playbackURL: URL? {
        playback.flatMap(URL.init(string:))
    }
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
        let container = try decoder.container(keyedBy: CodingKeys.self)
        instructions = (try? container.decodeIfPresent(String.self, forKey: .instructions)) ?? ""
        defaultVisible = (try? container.decodeIfPresent(Bool.self, forKey: .defaultVisible)) ?? true
    }
}
