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
    let userName: String?
    let userEmail: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case message, kind
        case userName = "user_name"
        case userEmail = "user_email"
        case createdAt = "created_at"
    }
}

struct PadEnvironment: Decodable, Identifiable, Hashable {
    let id: Int
    let language: String?
    let title: String?
    let contents: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, language, title, contents
        case createdAt = "created_at"
        case updatedAt = "updated_at"
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

    enum CodingKeys: String, CodingKey {
        case id, title, language, notes
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
    var takeHome: Bool?
    var padType: String?
    var candidateInstructions: [CandidateInstructionPayload]?

    enum CodingKeys: String, CodingKey {
        case title, language, description, solution
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
    var takeHome: Bool?
    var padType: String?
    var candidateInstructions: [CandidateInstructionPayload]?

    enum CodingKeys: String, CodingKey {
        case id, title, language, description, solution
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
    let createdAt: Date?
    let updatedAt: Date?
    let candidateInstructions: [CandidateInstruction]

    enum CodingKeys: String, CodingKey {
        case id, title, language, description, shared, used, solution
        case ownerEmail = "owner_email"
        case takeHome = "take_home"
        case testCasesEnabled = "test_cases_enabled"
        case padType = "pad_type"
        case isDraft = "is_draft"
        case authorName = "author_name"
        case organizationName = "organization_name"
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
        createdAt = c.loggedDecodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = c.loggedDecodeIfPresent(Date.self, forKey: .updatedAt)
        candidateInstructions = c.loggedDecodeIfPresent([CandidateInstruction].self, forKey: .candidateInstructions) ?? []
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

    enum CodingKeys: String, CodingKey {
        case id, users, teams
        case organizationName = "organization_name"
        case userCount = "user_count"
        case organizationDefaultLanguage = "organization_default_language"
        case singleSignOnSupported = "single_sign_on_supported"
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

    enum CodingKeys: String, CodingKey {
        case unlimited
        case trialExpiresAt = "trial_expires_at"
        case padsUsed = "pads_used"
        case quotaReset = "quota_reset_at"
        case overagesEnabled = "overages_enabled"
    }
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

    func listPads() async throws -> [Pad] {
        struct Wrapper: Decodable { let pads: [Pad] }
        return try await fetch(Wrapper.self, path: "/api/pads/").pads
    }

    func getPad(id: String) async throws -> Pad {
        struct Wrapper: Decodable { let pad: Pad }
        return try await fetch(Wrapper.self, path: "/api/pads/\(id)").pad
    }

    func padEvents(padID: String) async throws -> [PadEvent] {
        struct Wrapper: Decodable { let events: [PadEvent] }
        return try await fetch(Wrapper.self, path: "/api/pads/\(padID)/events").events
    }

    func padEnvironment(id: Int) async throws -> PadEnvironment {
        struct Wrapper: Decodable { let pad_environment: PadEnvironment }
        return try await fetch(Wrapper.self, path: "/api/pad_environments/\(id)").pad_environment
    }

    func createPad(_ body: PadCreate) async throws -> Pad {
        struct Wrapper: Decodable { let pad: Pad }
        return try await send(Wrapper.self, method: "POST", path: "/api/pads/", body: body).pad
    }

    func updatePad(_ body: PadUpdate) async throws -> Pad {
        struct Wrapper: Decodable { let pad: Pad }
        return try await send(Wrapper.self, method: "PUT", path: "/api/pads/", body: body).pad
    }

    // MARK: Questions

    func listQuestions() async throws -> [Question] {
        struct Wrapper: Decodable { let questions: [Question] }
        return try await fetch(Wrapper.self, path: "/api/questions/").questions
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

    // MARK: Plumbing

    private func fetch<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        guard !apiKey.isEmpty else { throw CoderPadError.missingAPIKey }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await performWithRetry(type, request: request)
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
