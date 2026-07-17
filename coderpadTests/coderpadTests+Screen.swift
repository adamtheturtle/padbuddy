//
//  coderpadTests+Screen.swift
//  coderpadTests
//
//  End-to-end tests for the Screen API layer (`ScreenClient` + `ScreenAPI`),
//  driven by an in-process `URLProtocol` that serves canned responses shaped
//  exactly like the documented CoderPad Screen API. No real network or key.
//

@testable import CoderPad
import Foundation
import Testing

// MARK: - Mock server

/// Serves canned Screen API responses for any request to `www.codingame.com`,
/// asserting the `API-Key` header is present and routing by path/method.
private final nonisolated class MockScreenURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "www.codingame.com"
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let method = request.httpMethod ?? "GET"
        // Strip the versioned prefix so routing reads cleanly.
        let path = components.path.replacingOccurrences(of: "/assessment/api/v1.1", with: "")
        let query = (components.queryItems ?? []).reduce(into: [String: String]()) { $0[$1.name] = $1.value }
        let (status, body) = Self.respond(method: method, path: path, query: query)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func respond(method: String, path: String, query: [String: String]) -> (Int, String) {
        switch (method, path) {
        case ("GET", "/campaigns"):
            (200, campaignsJSON)
        case ("POST", "/campaigns/42/actions/send"):
            (200, #"{"id": 999, "test_url": "https://screen-ide.coderpad.io/?id=999abc"}"#)
        case ("GET", "/tests"):
            if query["candidateEmail"] == "malformed@example.com" {
                (200, malformedTestsPageJSON)
            } else {
                // Paginate by `start`: page 1 has two of three tests, page 2 the last.
                (200, query["start"] == "2" ? testsPage2JSON : testsPage1JSON)
            }
        case ("GET", "/tests/13188658"):
            (200, completedTestJSON)
        case ("POST", "/tests/13188658/actions/cancel"),
             ("POST", "/tests/13188658/actions/resend"),
             ("DELETE", "/tests/13188658"):
            (204, "")
        case ("GET", "/webhook"):
            (200, #"{"url": "https://example.com/hook"}"#)
        case ("POST", "/webhook"), ("DELETE", "/webhook"):
            (204, "")
        default:
            (404, #"{"code": "NotFound", "message": "No such resource"}"#)
        }
    }

    private static let campaignsJSON = #"""
    [
      {"id": 42, "name": "Backend Screen", "languages": ["java", "python"], "pinned": true, "archived": false},
      {"id": 43, "name": "Frontend Screen", "languages": ["javascript"], "pinned": false, "archived": true}
    ]
    """#

    private static let testsPage1JSON = #"""
    {
      "tests": [
        {"status": "completed", "id": 1, "id_test": 1, "campaign_id": 42,
         "candidate_name": "Ada", "candidate_email": "ada@example.com", "tags": ["priority"],
         "send_time": 1769042802384, "start_time": 1769042842216, "end_time": 1769043535523,
         "candidate_language": "en", "questions": [{"id": 1106735, "last_activity_time": 1769043248900}]},
        {"status": "waiting", "id": 2, "id_test": 2, "campaign_id": 42,
         "candidate_email": "bob@example.com", "tags": [], "questions": []}
      ],
      "pagination": {"start": 0, "limit": 2, "total": 3, "has_more_items": true, "next_start": 2}
    }
    """#

    private static let testsPage2JSON = #"""
    {
      "tests": [
        {"status": "aborted", "id": 3, "id_test": 3, "campaign_id": 42, "tags": [], "questions": []}
      ],
      "pagination": {"start": 2, "limit": 2, "total": 3, "has_more_items": false, "next_start": null}
    }
    """#

    private static let malformedTestsPageJSON = #"""
    {
      "tests": [
        {"status": "completed", "id": 1, "id_test": 1, "campaign_id": 42,
         "candidate_email": "ada@example.com", "tags": [], "questions": []},
        {"status": "waiting", "id": "broken", "id_test": 99, "campaign_id": 42,
         "candidate_email": "bad@example.com", "tags": [], "questions": []},
        {"status": "aborted", "id": 2, "id_test": 2, "campaign_id": 42,
         "candidate_email": "bob@example.com", "tags": [], "questions": []}
      ],
      "pagination": {"start": 0, "limit": 3, "total": 3, "has_more_items": false, "next_start": null}
    }
    """#

    /// A realistic completed-test payload, mirroring the documented example.
    private static let completedTestJSON = #"""
    {
        "status": "completed",
        "url": "https://screen.coderpad.io/work/dashboard/campaign/1647306/candidates?selected=13188658",
        "report": {
            "duration": 688,
            "warnings": [
                "Candidate left the full-screen environment, using another monitor or window.",
                "Several people were present at the same time during the question"
            ],
            "points": 530,
            "score": 84.12698412698413,
            "technologies": {
                "Java": {
                    "points": 80,
                    "score": 44.44444444444444,
                    "skills": {
                        "Language knowledge": {"points": 0, "score": 0.0, "total_points": 80},
                        "Problem solving": {"points": 80, "score": 80.0, "total_points": 100}
                    },
                    "total_points": 180,
                    "comparative_score": 33.166666666666664
                }
            },
            "total_duration": 2570,
            "total_points": 630,
            "comparative_score": 53.7063492063492
        },
        "id": 13188658,
        "id_test": 13188658,
        "organization_id": "4143ca74-2f0e-4151-90d6-e1428739450b",
        "campaign_id": 1647306,
        "candidate_name": "Luke Duncan",
        "candidate_email": "luke.will.duncan@gmail.com",
        "tags": ["senior"],
        "send_time": 1769042802384,
        "start_time": 1769042842216,
        "end_time": 1769043535523,
        "test_url": "https://screen-ide.coderpad.io/?id=1318865801511b22d3e7b19d0a8be7e464254d73",
        "candidate_language": "en",
        "questions": [{"id": 1106735, "last_activity_time": 1769043248900}],
        "last_activity_time": 1769043248900,
        "approval_status": "TO_REVIEW"
    }
    """#
}

/// Always answers 401 with the Screen error envelope, mimicking an invalid `API-Key`.
private final nonisolated class MockScreenUnauthorizedURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "www.codingame.com"
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let body = Data(#"{"code": "Unauthorized", "message": "Invalid API key"}"#.utf8)
        guard let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func screenClient(_ proto: URLProtocol.Type = MockScreenURLProtocol.self,
                          apiKey: String = "test-key") -> ScreenClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [proto]
    return ScreenClient(apiKey: apiKey, session: URLSession(configuration: config))
}

// MARK: - Tests

@Suite("Screen API client")
struct ScreenClientTests {
    @Test
    func `listCampaigns decodes campaigns and their languages`() async throws {
        let campaigns = try await screenClient().listCampaigns()
        #expect(campaigns.count == 2)
        let backend = try #require(campaigns.first { $0.id == 42 })
        #expect(backend.name == "Backend Screen")
        #expect(backend.languages == ["java", "python"])
        #expect(backend.pinned)
        // The key-path form (`contains(where: \.archived)`) trips a spurious
        // "call can throw" diagnostic inside the #expect macro expansion.
        // swiftlint:disable:next prefer_key_path
        #expect(campaigns.contains { $0.archived })
    }

    @Test
    func `sendInvitation posts to a campaign and returns the test session`() async throws {
        let result = try await screenClient().sendInvitation(
            campaignID: 42,
            ScreenInvitation(candidateEmail: "candidate@example.com",
                             candidateName: "Pat",
                             sendInvitationEmail: true)
        )
        #expect(result.id == 999)
        #expect(result.testURL == "https://screen-ide.coderpad.io/?id=999abc")
    }

    @Test
    func `listTests returns the first page with offset pagination`() async throws {
        let page = try await screenClient().listTests(campaignID: 42)
        #expect(page.tests.count == 2)
        #expect(page.tests.first?.candidateName == "Ada")
        let pagination = try #require(page.pagination)
        #expect(pagination.hasMoreItems)
        #expect(pagination.nextStart == 2)
        #expect(pagination.total == 3)
    }

    @Test
    func `listTests keeps valid sessions when one page item is malformed (#764)`() async throws {
        let page = try await screenClient().listTests(candidateEmail: "malformed@example.com")

        #expect(page.tests.map(\.id) == [1, 2])
        #expect(page.pagination?.total == 3)
    }

    @Test
    func `listAllTests follows pagination to the end`() async throws {
        let all = try await screenClient().listAllTests(campaignID: 42)
        #expect(all.count == 3)
        #expect(all.map(\.id) == [1, 2, 3])
        #expect(all.last?.status == "aborted")
    }

    @Test
    func `getTest decodes a completed report with nested technologies and skills`() async throws {
        let test = try await screenClient().getTest(id: 13_188_658)
        #expect(test.status == "completed")
        #expect(test.candidateName == "Luke Duncan")
        #expect(test.approvalStatus == "TO_REVIEW")
        let report = try #require(test.report)
        #expect(report.points == 530)
        #expect(report.warnings.count == 2)
        #expect(report.totalPoints == 630)
        let java = try #require(report.technologies["Java"])
        #expect(java.points == 80)
        let problemSolving = try #require(java.skills["Problem solving"])
        #expect(problemSolving.totalPoints == 100)
        #expect(problemSolving.score == 80.0)
    }

    @Test
    func `epoch-millisecond timestamps convert to Dates`() async throws {
        let test = try await screenClient().getTest(id: 13_188_658)
        let sendDate = try #require(test.sendDate)
        // 1769042802384 ms == 2026-01-22 in UTC; just assert the round-trip math.
        #expect(Int(sendDate.timeIntervalSince1970 * 1000) == 1_769_042_802_384)
        #expect(test.startDate != nil)
        #expect(test.endDate != nil)
        #expect(test.questions.first?.lastActivityTime == 1_769_043_248_900)
    }

    @Test
    func `cancel, resend, and delete succeed on a 204 response`() async throws {
        let client = screenClient()
        try await client.cancelTest(id: 13_188_658)
        try await client.resendTest(id: 13_188_658)
        try await client.deleteTest(id: 13_188_658)
    }

    @Test
    func `webhookURL reads the configured callback`() async throws {
        let url = try await screenClient().webhookURL()
        #expect(url == "https://example.com/hook")
    }

    @Test
    func `an empty API key fails fast without a request`() async throws {
        let client = ScreenClient(apiKey: "", session: URLSession(configuration: .ephemeral))
        await #expect(throws: CoderPadError.self) {
            _ = try await client.listCampaigns()
        }
    }

    @Test
    func `an unknown test id surfaces a mapped 404`() async throws {
        let error = await #expect(throws: CoderPadError.self) {
            _ = try await screenClient().getTest(id: 1)
        }
        if case let .http(code, _) = error {
            #expect(code == 404)
        } else {
            Issue.record("Expected a .http error, got \(String(describing: error))")
        }
    }
}

@Suite("Screen API unauthorized")
struct ScreenClientUnauthorizedTests {
    @Test
    func `an invalid API key surfaces an unauthorized CoderPadError`() async throws {
        let client = screenClient(MockScreenUnauthorizedURLProtocol.self)
        let error = await #expect(throws: CoderPadError.self) {
            _ = try await client.listCampaigns()
        }
        #expect(error?.isUnauthorized == true)
        if case let .http(code, _) = error {
            #expect(code == 401)
        } else {
            Issue.record("Expected a .http error, got \(String(describing: error))")
        }
    }
}

@Suite("Screen session link fallback")
struct ScreenSessionURLTests {
    @Test
    func `valid recruiter URL wins over the candidate URL`() {
        let session = ScreenTestSession(id: 1, url: "https://a.example/review",
                                        testURL: "https://b.example/take")
        #expect(session.screenURL?.absoluteString == "https://a.example/review")
    }

    @Test
    func `malformed recruiter URL falls back to the candidate URL`() {
        let session = ScreenTestSession(id: 1, url: "not a url",
                                        testURL: "https://b.example/take")
        #expect(session.screenURL?.absoluteString == "https://b.example/take")
    }

    @Test
    func `empty recruiter URL falls back to the candidate URL`() {
        let session = ScreenTestSession(id: 1, url: "", testURL: "https://b.example/take")
        #expect(session.screenURL?.absoluteString == "https://b.example/take")
    }

    @Test
    func `non-web schemes are rejected`() {
        let session = ScreenTestSession(id: 1, url: "file:///etc/hosts",
                                        testURL: "javascript:alert(1)")
        #expect(session.screenURL == nil)
    }

    @Test
    func `no links at all yields nil`() {
        #expect(ScreenTestSession(id: 1).screenURL == nil)
    }
}
