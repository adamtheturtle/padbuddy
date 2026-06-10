//
//  CoderPadAPI.swift
//  coderpad
//

import Foundation
import os.log

let apiLogger = Logger(subsystem: "com.coderpad.app", category: "api")

extension KeyedDecodingContainer {
    /// Like `try? decodeIfPresent`, but logs the underlying error so silent API drift
    /// shows up in Console rather than producing an empty UI with no diagnostic.
    func loggedDecodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        do {
            return try decodeIfPresent(type, forKey: key)
        } catch {
            apiLogger.debug("decodeIfPresent '\(key.stringValue, privacy: .public)' as \(String(describing: type), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

// MARK: - Models

struct Pad: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let state: String
    let ownerEmail: String
    let language: String?
    let participants: [String]
    let url: String
    let playback: String?
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
        case notes, drawing, contents, history
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
        participants = c.loggedDecodeIfPresent([String].self, forKey: .participants) ?? []
        url = c.loggedDecodeIfPresent(String.self, forKey: .url) ?? ""
        playback = c.loggedDecodeIfPresent(String.self, forKey: .playback)
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

struct PadTeam: Decodable, Hashable {
    let id: String
    let name: String
}

struct PadEvent: Decodable, Identifiable, Hashable {
    var id: String { "\(createdAt?.timeIntervalSince1970 ?? 0)-\(kind)-\(userName ?? "")-\(message.hashValue)" }
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
struct PadEnvironmentFile: Decodable, Hashable {
    let path: String?
    let contents: String?
    let history: String?
}

struct PadEnvironment: Decodable, Identifiable, Hashable {
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
    /// Set to `true` to end the interview. Any other value is ignored by the API.
    var ended: Bool?
    /// Set to `true` to delete the interview. Any other value is ignored by the API.
    var deleted: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, language, notes, ended, deleted
        case ownerEmail = "owner_email"
        case isPrivate = "private"
        case executionEnabled = "execution_enabled"
    }
}

struct QuestionCreate: Codable {
    var title: String
    var language: String?
    var description: String?
    var solution: String?
    /// Starter code inserted into the interview session when this question is used.
    var contents: String?
    var takeHome: Bool?
    var padType: String?
    var candidateInstructions: [CandidateInstructionPayload]?

    enum CodingKeys: String, CodingKey {
        case title, language, description, solution, contents
        case takeHome = "take_home"
        case padType = "pad_type"
        case candidateInstructions = "candidate_instructions"
    }
}

struct QuestionUpdate: Codable {
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

    enum CodingKeys: String, CodingKey {
        case id, title, language, description, solution, contents
        case takeHome = "take_home"
        case padType = "pad_type"
        case candidateInstructions = "candidate_instructions"
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

struct PadCreate: Codable {
    var title: String?
    var language: String?
    var ownerEmail: String?
    var contents: String?
    var notes: String?
    var isPrivate: Bool?
    var executionEnabled: Bool?
    var questionIDs: [Int]?

    enum CodingKeys: String, CodingKey {
        case title, language, contents, notes
        case ownerEmail = "owner_email"
        case isPrivate = "private"
        case executionEnabled = "execution_enabled"
        case questionIDs = "question_ids"
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
            questionIDs: [q.id]
        )
    }
}

struct Question: Decodable, Identifiable, Hashable {
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

struct QuestionCustomFile: Decodable, Hashable, Identifiable {
    let id: String?
    let title: String?
    let description: String?
    let filename: String?
    let filesize: String?
}

struct QuestionTestCase: Decodable, Hashable, Identifiable {
    let id: Int
    let returnValue: String?
    let visible: Bool?
    let arguments: [String]?

    enum CodingKeys: String, CodingKey {
        case id, visible, arguments
        case returnValue = "return_value"
    }
}

struct CandidateInstruction: Decodable, Hashable {
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

struct Organization: Decodable, Hashable {
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

struct OrganizationUser: Decodable, Identifiable, Hashable {
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

struct OrganizationStats: Decodable, Hashable {
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

struct Quota: Decodable, Hashable {
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
private protocol PagedResponse: Decodable {
    associatedtype Item: Decodable
    var pageItems: [Item] { get }
    var nextPage: String? { get }
}

private struct PadsPage: PagedResponse {
    let pads: [Pad]
    let nextPage: String?
    var pageItems: [Pad] { pads }
    enum CodingKeys: String, CodingKey { case pads; case nextPage = "next_page" }
}

private struct QuestionsPage: PagedResponse {
    let questions: [Question]
    let nextPage: String?
    var pageItems: [Question] { questions }
    enum CodingKeys: String, CodingKey { case questions; case nextPage = "next_page" }
}

private struct EventsPage: PagedResponse {
    let events: [PadEvent]
    let nextPage: String?
    var pageItems: [PadEvent] { events }
    enum CodingKeys: String, CodingKey { case events; case nextPage = "next_page" }
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
            return "HTTP \(code): \(body.prefix(300))"
        case .decode(let detail):
            return "Couldn't read response: \(detail)"
        }
    }

    var isUnauthorized: Bool {
        if case .http(401, _) = self { return true }
        if case .http(403, _) = self { return true }
        return false
    }
}

// MARK: - Client

struct CoderPadClient {
    let apiKey: String
    let baseURL = URL(string: "https://app.coderpad.io")!
    let session: URLSession

    init(apiKey: String, session: URLSession = CoderPadClient.liveSession) {
        self.apiKey = apiKey
        self.session = session
    }

    static let liveSession: URLSession = .shared

    static func live(apiKey: String) -> CoderPadClient {
        CoderPadClient(apiKey: apiKey, session: liveSession)
    }

    static func mock() -> CoderPadClient {
        CoderPadClient(apiKey: "demo", session: MockServer.session())
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = fractional.date(from: s) ?? basic.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrecognized date: \(s)")
        }
        return d
    }()

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

    func getPad(id: String) async throws -> Pad {
        struct Wrapper: Decodable { let pad: Pad }
        return try await fetch(Wrapper.self, path: "/api/pads/\(id)").pad
    }

    func padEvents(padID: String) async throws -> [PadEvent] {
        try await fetchAllPages(EventsPage.self, path: "/api/pads/\(padID)/events")
    }

    func padEnvironment(id: Int) async throws -> PadEnvironment {
        struct Wrapper: Decodable { let pad_environment: PadEnvironment }
        return try await fetch(Wrapper.self, path: "/api/pad_environments/\(id)").pad_environment
    }

    func createPad(_ body: PadCreate) async throws -> Pad {
        // Unlike the GET endpoints, POST /api/pads returns the pad fields at the top
        // level (alongside "status"), not nested under a "pad" key.
        return try await send(Pad.self, method: "POST", path: "/api/pads/", body: body)
    }

    func updatePad(_ body: PadUpdate) async throws -> Pad {
        struct Wrapper: Decodable { let pad: Pad }
        return try await send(Wrapper.self, method: "PUT", path: "/api/pads/", body: body).pad
    }

    /// Ends the interview. The live API replies `{"status":"OK"}` with no pad body.
    func endPad(id: String) async throws {
        struct StatusOnly: Decodable { let status: String? }
        _ = try await send(StatusOnly.self, method: "PUT", path: "/api/pads/",
                           body: PadUpdate(id: id, ended: true))
    }

    /// Deletes the interview. The live API replies `{"status":"OK"}` with no pad body.
    func deletePad(id: String) async throws {
        struct StatusOnly: Decodable { let status: String? }
        _ = try await send(StatusOnly.self, method: "PUT", path: "/api/pads/",
                           body: PadUpdate(id: id, deleted: true))
    }

    // MARK: Questions

    func listQuestions(sort: String? = nil) async throws -> [Question] {
        try await fetchAllPages(QuestionsPage.self, path: "/api/questions/", sort: sort)
    }

    func getQuestion(id: Int) async throws -> Question {
        struct Wrapper: Decodable { let question: Question }
        return try await fetch(Wrapper.self, path: "/api/questions/\(id)").question
    }

    func createQuestion(_ body: QuestionCreate) async throws -> Question {
        struct Wrapper: Decodable { let question: Question }
        return try await send(Wrapper.self, method: "POST", path: "/api/questions/", body: body).question
    }

    func updateQuestion(_ body: QuestionUpdate) async throws -> Question {
        struct Wrapper: Decodable { let question: Question }
        return try await send(Wrapper.self, method: "PUT", path: "/api/questions/\(body.id)", body: body).question
    }

    func deleteQuestion(id: Int) async throws {
        struct Empty: Decodable {}
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/questions/\(id)"))
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

    func organizationStats() async throws -> OrganizationStats {
        return try await fetch(OrganizationStats.self, path: "/api/organization/stats")
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
        struct Wrapper: Decodable { let users: [OrganizationUser] }
        guard !apiKey.isEmpty else { throw CoderPadError.missingAPIKey }
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/organization/users"),
                                  resolvingAgainstBaseURL: false)
        if let email { comps?.queryItems = [URLQueryItem(name: "email", value: email)] }
        guard let url = comps?.url else { throw CoderPadError.http(0, "Invalid URL") }
        return try await performWithRetry(Wrapper.self, request: authorizedGET(url)).users
    }

    // MARK: Plumbing

    private func authorizedGET(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func fetch<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        guard !apiKey.isEmpty else { throw CoderPadError.missingAPIKey }
        return try await performWithRetry(type, request: authorizedGET(baseURL.appendingPathComponent(path)))
    }

    /// Follows `next_page` links until the list is exhausted, accumulating every page.
    /// Without this, callers would silently receive only the first 50 records.
    private func fetchAllPages<W: PagedResponse>(_ type: W.Type, path: String, sort: String? = nil) async throws -> [W.Item] {
        guard !apiKey.isEmpty else { throw CoderPadError.missingAPIKey }
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if let sort { comps?.queryItems = [URLQueryItem(name: "sort", value: sort)] }
        var url = comps?.url
        var items: [W.Item] = []
        var pages = 0
        while let current = url {
            let page = try await performWithRetry(W.self, request: authorizedGET(current))
            items.append(contentsOf: page.pageItems)
            pages += 1
            // Safety valve against a server that keeps handing back next_page links.
            guard pages < 1000, let next = page.nextPage, let nextURL = URL(string: next) else { break }
            url = nextURL
        }
        return items
    }

    /// GET requests are idempotent, so transient failures (5xx, 429, network timeouts)
    /// are retried with exponential backoff before the error surfaces to the UI. Mutating
    /// requests go straight through `perform` to avoid duplicating side effects.
    private func performWithRetry<T: Decodable>(_ type: T.Type, request: URLRequest, maxAttempts: Int = 3) async throws -> T {
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

    private static func isTransient(_ error: Error) -> Bool {
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

    private func send<T: Decodable, B: Encodable>(_ type: T.Type, method: String, path: String, body: B) async throws -> T {
        guard !apiKey.isEmpty else { throw CoderPadError.missingAPIKey }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder.encode(body)
        return try await perform(type, request: request)
    }

    private func perform<T: Decodable>(_ type: T.Type, request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CoderPadError.http(0, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CoderPadError.http(http.statusCode, body)
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
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

    private func pathString(_ keys: [CodingKey]) -> String {
        keys.map { $0.stringValue }.joined(separator: ".")
    }
}
