//
//  CoderPadClient.swift
//  coderpad
//
//  The networking client and the paginated/decode-only response envelopes it
//  consumes. The low-level request, pagination, and decoding plumbing lives in
//  `CoderPadClient+Plumbing.swift`.
//

import Foundation
import os.log

// MARK: - Pagination

/// A list response that may span multiple pages. The API returns at most 50 items
/// per page, plus an absolute `next_page` URL when more remain. Callers that ignore
/// it silently see only the first page.
///
/// `total` (the count across all pages, when the endpoint reports it) lets the client
/// compute the page count from the first response and fetch the rest concurrently,
/// rather than walking `next_page` one blocking round-trip at a time.
protocol PagedResponse: Decodable, Sendable {
    associatedtype Item: Decodable & Sendable
    // `nonisolated` so the pagination pipeline can read these off the main actor
    // (see `streamAllPages`); without it the module's default MainActor isolation
    // would make the protocol requirements main-actor-isolated.
    nonisolated var pageItems: [Item] { get }
    nonisolated var nextPage: String? { get }
    nonisolated var total: Int? { get }
    /// A stable identity used to de-duplicate items when stitching parallel pages,
    /// so a server that echoes page 1 for an over-requested `page` can't produce
    /// duplicate rows. `nil` opts out (e.g. events, which have no stable unique id
    /// and take the sequential path anyway).
    nonisolated static func identity(of item: Item) -> AnyHashable?
}

extension PagedResponse {
    nonisolated static func identity(of _: Item) -> AnyHashable? { nil }
}

private nonisolated struct PadsPage: PagedResponse {
    let pads: [Pad]
    let nextPage: String?
    let total: Int?
    var pageItems: [Pad] {
        pads
    }

    static func identity(of item: Pad) -> AnyHashable? { item.id }

    enum CodingKeys: String, CodingKey { case pads; case nextPage = "next_page"; case total }
}

private nonisolated struct QuestionsPage: PagedResponse {
    let questions: [Question]
    let nextPage: String?
    let total: Int?
    var pageItems: [Question] {
        questions
    }

    static func identity(of item: Question) -> AnyHashable? { item.id }

    enum CodingKeys: String, CodingKey { case questions; case nextPage = "next_page"; case total }
}

private nonisolated struct EventsPage: PagedResponse {
    let events: [PadEvent]
    let nextPage: String?
    let total: Int?
    var pageItems: [PadEvent] {
        events
    }

    enum CodingKeys: String, CodingKey { case events; case nextPage = "next_page"; case total }
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

    /// The API mixes fractional- and whole-second ISO-8601 timestamps, so we try both.
    /// `ISO8601DateFormatter` is thread-safe for parsing and these are configured once
    /// and only ever read, so sharing them across the off-main decodes is safe — the
    /// `unsafe` vouches for that, since the type isn't formally `Sendable`.
    private nonisolated(unsafe) static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let basicDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Builds a configured decoder. A factory rather than a shared instance because
    /// decoding runs off the main actor (see `perform`), and `JSONDecoder` isn't safe
    /// to share across threads — each background decode gets its own.
    nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = fractionalDateFormatter.date(from: raw) ?? basicDateFormatter.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(raw)")
        }
        return decoder
    }

    /// Shared decoder for callers that decode on the current actor (e.g. tests).
    /// The network path decodes off-main via `makeDecoder()` instead.
    static let decoder: JSONDecoder = makeDecoder()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
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
        try await send(Pad.self, method: "POST", path: "/api/pads/", body: body)
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
        try await send(Question.self, method: "POST", path: "/api/questions/", body: body)
    }

    /// The live API replies `{"status":"OK"}` with no question body, so we re-fetch the
    /// question to return its fresh server state rather than decoding the (absent) body.
    func updateQuestion(_ body: QuestionUpdate) async throws -> Question {
        _ = try await send(StatusOnly.self, method: "PUT", path: "/api/questions/\(body.id)", body: body)
        return try await getQuestion(id: body.id)
    }

    func deleteQuestion(id: Int) async throws {
        guard !apiKey.isEmpty else { throw CoderPadError.missingAPIKey }
        var request = URLRequest(url: baseURL.appending(path: "/api/questions/\(id)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        _ = try await perform(Empty.self, request: request)
    }

    // MARK: Quota / Organization

    func quota() async throws -> Quota {
        try await fetch(Quota.self, path: "/api/quota")
    }

    func organization() async throws -> Organization {
        try await fetch(Organization.self, path: "/api/organization")
    }

    /// Pad usage stats for the organization. With no range the API reports the
    /// last 7 days; passing `start`/`end` configures the window (both are required
    /// together, per the API contract).
    func organizationStats(start: Date? = nil, end: Date? = nil) async throws -> OrganizationStats {
        guard !apiKey.isEmpty else { throw CoderPadError.missingAPIKey }
        var comps = URLComponents(url: baseURL.appending(path: "/api/organization/stats"),
                                  resolvingAgainstBaseURL: false)
        if let start, let end {
            comps?.queryItems = [
                URLQueryItem(name: "start_time", value: start.formatted(.iso8601)),
                URLQueryItem(name: "end_time", value: end.formatted(.iso8601))
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
        var comps = URLComponents(url: baseURL.appending(path: "/api/organization/users"),
                                  resolvingAgainstBaseURL: false)
        if let email { comps?.queryItems = [URLQueryItem(name: "email", value: email)] }
        guard let url = comps?.url else { throw CoderPadError.http(0, "Invalid URL") }
        return try await performWithRetry(Wrapper.self, request: authorizedGET(url)).users
    }
}
