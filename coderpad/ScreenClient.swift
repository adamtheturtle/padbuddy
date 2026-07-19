//
//  ScreenClient.swift
//  coderpad
//
//  Networking client for the CoderPad Screen API (https://api.screen.coderpad.io).
//  A thin, self-contained client rather than a `PaginatedRESTClient` wrapper like
//  `CoderPadClient`, because Screen differs from the Interview API in three ways:
//  it authenticates with an `API-Key` header (not a bearer token), it paginates
//  by offset (`start`/`limit`) instead of a `next_page` cursor URL, and all its
//  timestamps are epoch-millisecond integers (no ISO-8601 date parsing needed).
//
//  Failures are mapped onto the app's existing `CoderPadError` so callers (and
//  the unauthorized/offline UI states) handle Screen and Interview errors the
//  same way — both are CoderPad products and the error envelope (`{"code","message"}`)
//  carries a `message` that `CoderPadError` already surfaces.
//

import Foundation

struct ScreenClient {
    // Immutable, Sendable configuration driving pure networking, so these are
    // `nonisolated`: the request methods can run off the main actor rather than
    // being pinned to it by the module's default MainActor isolation.
    nonisolated let apiKey: String
    nonisolated let baseURL: URL
    nonisolated let session: URLSession

    /// The US server. EU customers override with `euBaseURL`.
    static let defaultBaseURL = URL.staticURL("https://www.codingame.com")
    /// The EU server, for organizations hosted in the EU region.
    static let euBaseURL = URL.staticURL("https://www.codingame.eu")

    /// All endpoints live under this versioned prefix. The version is bumped only
    /// for breaking changes (added response fields are non-breaking — see `ScreenAPI`).
    private nonisolated static let apiPrefix = "/assessment/api/v1.1"
    nonisolated static let maximumPageSize = 500
    nonisolated static let maximumProductFilterLength = 64
    nonisolated static let maximumEmailFilterLength = 320
    nonisolated static let maximumErrorBodyBytes = 16 * 1024
    nonisolated static let maximumFullListPages = 100
    nonisolated static let maximumFullListItems = 10000

    init(apiKey: String,
         baseURL: URL = Self.defaultBaseURL,
         session: URLSession = Self.liveSession) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
    }

    /// The single construction point for the live session, mirroring `CoderPadClient`.
    static let liveSession: URLSession = .init(configuration: makeLiveConfiguration())

    /// Kept separate from the session so timeout policy is directly testable.
    nonisolated static func makeLiveConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return config
    }

    static func live(apiKey: String, baseURL: URL = Self.defaultBaseURL) -> Self {
        Self(apiKey: apiKey, baseURL: baseURL, session: liveSession)
    }

    // MARK: Campaigns

    /// All test campaigns in the organization. `GET /campaigns`. Decoded tolerantly:
    /// one malformed campaign in the response is dropped rather than hiding every
    /// valid campaign behind a decode error (#896), matching the sessions page (#764).
    nonisolated func listCampaigns() async throws -> [ScreenCampaign] {
        try await listCampaignsResult().campaigns
    }

    nonisolated func listCampaignsResult() async throws -> ScreenCampaignListResult {
        let list = try await get(TolerantScreenList<ScreenCampaign>.self, path: "/campaigns")
        return ScreenCampaignListResult(campaigns: list.elements, discardedCount: list.discardedCount)
    }

    /// Invites a candidate to a campaign, creating a test session.
    /// `POST /campaigns/:id/actions/send`.
    nonisolated func sendInvitation(campaignID: Int,
                                    _ invitation: ScreenInvitation) async throws -> ScreenInvitationResult {
        try Self.requirePositiveID(campaignID, kind: "campaign")
        try await send(ScreenInvitationResult.self,
                       method: "POST",
                       path: "/campaigns/\(campaignID)/actions/send",
                       body: invitation)
    }

    // MARK: Test sessions

    /// One page of test sessions. `GET /tests`. All filters are optional; the API
    /// reports `pagination.nextStart`/`hasMoreItems` for paging, or use
    /// `listAllTests` to follow every page.
    nonisolated func listTests(campaignID: Int? = nil,
                               product: String? = nil,
                               candidateEmail: String? = nil,
                               from: Int? = nil,
                               until: Int? = nil,
                               start: Int? = nil,
                               limit: Int? = nil) async throws -> ScreenTestsPage {
        if let campaignID { try Self.requirePositiveID(campaignID, kind: "campaign") }
        let filters = try Self.normalizedListFilters(product: product, candidateEmail: candidateEmail)
        if let start, start < 0 {
            throw CoderPadError.decode("Screen pagination start must not be negative.")
        }
        if let limit, !(1 ... Self.maximumPageSize).contains(limit) {
            throw CoderPadError.decode("Screen pagination limit must be between 1 and \(Self.maximumPageSize).")
        }
        var query: [URLQueryItem] = []
        if let campaignID { query.append(URLQueryItem(name: "campaignId", value: String(campaignID))) }
        if let product = filters.product { query.append(URLQueryItem(name: "product", value: product)) }
        if let candidateEmail = filters.candidateEmail {
            query.append(URLQueryItem(name: "candidateEmail", value: candidateEmail))
        }
        if let from { query.append(URLQueryItem(name: "from", value: String(from))) }
        if let until { query.append(URLQueryItem(name: "to", value: String(until))) }
        if let start { query.append(URLQueryItem(name: "start", value: String(start))) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        return try await get(ScreenTestsPage.self, path: "/tests", query: query)
    }

    /// Every test session matching the filters, following offset pagination to the
    /// end. Convenience over `listTests` for callers that want the full list.
    nonisolated func listAllTests(campaignID: Int? = nil,
                                  product: String? = nil,
                                  candidateEmail: String? = nil,
                                  from: Int? = nil,
                                  until: Int? = nil) async throws -> [ScreenTestSession] {
        var all: [ScreenTestSession] = []
        // Offset pagination can shift while pages are fetched, re-serving a session
        // on a later page; keep the first copy of each id so callers never see
        // duplicates (#898). (A concurrent deletion can still skip a session - not
        // detectable client-side with offset paging.)
        var seenIDs: Set<Int> = []
        // Server-provided offsets already visited: a `nextStart` cycle spanning more
        // than one page (A -> B -> A) would otherwise loop forever (#857).
        var seenStarts: Set<Int> = []
        var start: Int?
        var pageCount = 0
        while true {
            guard pageCount < Self.maximumFullListPages else {
                throw CoderPadError.decode("Screen pagination exceeded the maximum page count.")
            }

            pageCount += 1
            let page = try await listTests(campaignID: campaignID,
                                           product: product,
                                           candidateEmail: candidateEmail,
                                           from: from,
                                           until: until,
                                           start: start)
            let additions = page.tests.filter { seenIDs.insert($0.id).inserted }
            guard additions.count <= Self.maximumFullListItems - all.count else {
                throw CoderPadError.decode("Screen pagination exceeded the maximum item count.")
            }

            all.append(contentsOf: additions)
            guard let pagination = page.pagination, pagination.hasMoreItems else { break }

            // The API says more items exist but gave no usable way to fetch them:
            // surface that instead of silently returning a partial list (#858).
            guard let next = pagination.nextStart, next != start, seenStarts.insert(next).inserted else {
                throw CoderPadError.decode("Screen pagination returned an invalid next offset.")
            }

            start = next
        }
        return all
    }

    /// A single test session's status and (once finished) report. `GET /tests/:id`.
    /// `withCommunityStats` adds the report's community score distribution.
    nonisolated func getTest(id: Int, withCommunityStats: Bool = false) async throws -> ScreenTestSession {
        try Self.requirePositiveID(id, kind: "test")
        let query = withCommunityStats ? [URLQueryItem(name: "withCommunityStats", value: "true")] : []
        return try await get(ScreenTestSession.self, path: "/tests/\(id)", query: query)
    }

    /// Cancels a not-yet-started test invitation. `POST /tests/:id/actions/cancel`.
    nonisolated func cancelTest(id: Int) async throws {
        try Self.requirePositiveID(id, kind: "test")
        try await sendNoContent(method: "POST", path: "/tests/\(id)/actions/cancel")
    }

    /// Resends the invitation email for a test. `POST /tests/:id/actions/resend`.
    nonisolated func resendTest(id: Int) async throws {
        try Self.requirePositiveID(id, kind: "test")
        try await sendNoContent(method: "POST", path: "/tests/\(id)/actions/resend")
    }

    /// Deletes a test session. `DELETE /tests/:id`.
    nonisolated func deleteTest(id: Int) async throws {
        try Self.requirePositiveID(id, kind: "test")
        try await sendNoContent(method: "DELETE", path: "/tests/\(id)")
    }

    /// The candidate's report as a PDF. `GET /tests/:id/report`. Returns the raw
    /// PDF bytes; `reportType` selects the report variant when the API offers more
    /// than one.
    nonisolated func testReport(id: Int,
                                reportType: String? = nil,
                                anonymous: Bool? = nil,
                                includeRank: Bool? = nil,
                                includeComparativeScore: Bool? = nil) async throws -> Data {
        try Self.requirePositiveID(id, kind: "test")
        var query: [URLQueryItem] = []
        if let reportType { query.append(URLQueryItem(name: "report_type", value: reportType)) }
        if let anonymous { query.append(URLQueryItem(name: "anonymous", value: String(anonymous))) }
        if let includeRank { query.append(URLQueryItem(name: "include_rank", value: String(includeRank))) }
        if let includeComparativeScore {
            query.append(URLQueryItem(name: "include_comparative_score", value: String(includeComparativeScore)))
        }
        let request = try authorizedRequest(path: "/tests/\(id)/report", method: "GET",
                                            query: query, accept: "application/pdf")
        let (data, response) = try await reportData(for: request)
        // A 2xx that isn't actually a PDF (an HTML error page, an empty body) must
        // not be opened or saved as a candidate report (#859).
        let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? ""
        let mediaType = contentType.split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard mediaType == "application/pdf", data.starts(with: Array("%PDF-".utf8)) else {
            throw CoderPadError.decode("The report response was not a PDF.")
        }

        return data
    }

    // MARK: - Transport

    /// Builds an authorized request, attaching the `API-Key` header that every
    /// Screen endpoint requires.
    private nonisolated func authorizedRequest(path: String,
                                               method: String,
                                               query: [URLQueryItem] = [],
                                               accept: String = "application/json") throws -> URLRequest {
        guard !apiKey.isEmpty else { throw CoderPadError.missingAPIKey }
        guard baseURL.scheme?.lowercased() == "https", baseURL.host?.isEmpty == false,
              baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil else {
            throw CoderPadError.decode("Screen base URL must be a credential-free HTTPS origin.")
        }

        var components = URLComponents(url: baseURL.appending(path: Self.apiPrefix + path),
                                       resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw CoderPadError.http(0, "Invalid URL") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "API-Key")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return request
    }

    nonisolated func get<T: Decodable>(
        _ type: T.Type,
        path: String,
        query: [URLQueryItem] = []
    ) async throws -> T {
        let request = try authorizedRequest(path: path, method: "GET", query: query)
        return try await decode(type, from: data(for: request).0)
    }

    private nonisolated func send<T: Decodable>(_ type: T.Type,
                                                method: String,
                                                path: String,
                                                body: some Encodable) async throws -> T {
        var request = try authorizedRequest(path: path, method: method)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(body)
        return try await decode(type, from: data(for: request).0)
    }

    /// For the 204-No-Content actions (cancel/resend/delete/webhook). An optional
    /// JSON body covers `POST /webhook`, whose body is a bare URL string.
    nonisolated func sendNoContent(
        method: String,
        path: String,
        body: (some Encodable)? = String?.none
    ) async throws {
        var request = try authorizedRequest(path: path, method: method)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encode(body)
        }
        _ = try await data(for: request)
    }

    /// Runs the request, mapping transport failures to `CoderPadError.network` and
    /// non-2xx responses to `CoderPadError.http` (carrying the body so the API's
    /// `message` can surface), matching `CoderPadClient`'s behavior.
    @discardableResult
    private nonisolated func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            if urlError.code == .cancelled { throw CancellationError() }
            throw CoderPadError.network(urlError)
        }
        guard let http = response as? HTTPURLResponse else {
            throw CoderPadError.http(0, "No HTTP response")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            // Bound the extra copy retained by CoderPadError and any eventual UI/log
            // presentation. URLSession has already received `data`; this specifically
            // prevents duplicating an arbitrarily large server body as a String (#2771).
            let bounded = data.prefix(Self.maximumErrorBodyBytes)
            throw CoderPadError.http(http.statusCode, String(bytes: bounded, encoding: .utf8) ?? "")
        }

        return (data, http)
    }

    /// One coder each for every Screen call, rather than one per request/response.
    ///
    /// Screen carries no ISO-8601 dates (timestamps are epoch-millisecond ints), so the
    /// default configuration suffices and nothing here mutates their options — which is
    /// what made the per-call allocation pure waste on every request, including each
    /// page of `listAllTests` (#2115). Both types are safe to use concurrently as long
    /// as they are only read, so `nonisolated(unsafe)` covers the off-main decodes,
    /// matching `WidgetPadSnapshot`'s shared pair.
    private nonisolated(unsafe) static let decoder = JSONDecoder()
    private nonisolated(unsafe) static let encoder = JSONEncoder()

    private nonisolated func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try Self.decoder.decode(type, from: data)
        } catch {
            throw CoderPadError.decode(String(describing: error))
        }
    }

    private nonisolated func encode(_ body: some Encodable) throws -> Data {
        try Self.encoder.encode(body)
    }
}

nonisolated struct ScreenCampaignListResult: Equatable {
    let campaigns: [ScreenCampaign]
    let discardedCount: Int

    var diagnostic: String? {
        guard discardedCount > 0 else { return nil }

        return "Ignored \(discardedCount) malformed campaign \(discardedCount == 1 ? "record" : "records") from Screen."
    }
}

private extension ScreenClient {
    nonisolated static func requirePositiveID(_ id: Int, kind: String) throws {
        guard id > 0 else { throw CoderPadError.decode("Screen \(kind) ID must be positive.") }
    }

    nonisolated static func normalizedFilter(_ raw: String?, name: String, maximumLength: Int) throws -> String? {
        guard let raw else { return nil }

        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= maximumLength,
              !value.unicodeScalars.contains(where: { scalar in
                  let category = scalar.properties.generalCategory
                  return category == .control || category == .format
              }) else {
            throw CoderPadError.decode("Screen \(name) filter is invalid or too long.")
        }

        return value
    }

    nonisolated static func normalizedListFilters(product: String?, candidateEmail: String?) throws
        -> (product: String?, candidateEmail: String?) {
        let product = try normalizedFilter(product, name: "product", maximumLength: maximumProductFilterLength)
        let candidateEmail = try normalizedFilter(
            candidateEmail, name: "candidate email", maximumLength: maximumEmailFilterLength
        ).map(EmailValidation.normalized)
        if let candidateEmail, !EmailValidation.isPlausibleAddress(candidateEmail) {
            throw CoderPadError.decode("Screen candidate email filter is invalid or too long.")
        }
        return (product, candidateEmail)
    }
}
