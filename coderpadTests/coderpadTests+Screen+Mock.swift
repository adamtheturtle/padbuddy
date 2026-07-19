//
//  coderpadTests+Screen+Mock.swift
//  coderpadTests
//
//  The mock Screen server behind ScreenClientTests: URLProtocol stubs for the
//  happy-path fixtures, the pagination edge cases (#857/#858/#898), the PDF and
//  non-PDF report responses (#859), and the unauthorized variant. Split from
//  coderpadTests+Screen.swift to keep it within the lint length limit.
//

@testable import CoderPad
import Foundation

final nonisolated class ScreenAPIMockURLProtocol: URLProtocol {
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
        let contentType = body.hasPrefix("%PDF") ? "application/pdf" : "application/json"
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": contentType]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    // swiftlint:disable:next cyclomatic_complexity
    private static func respond(method: String, path: String, query: [String: String]) -> (Int, String) {
        switch (method, path) {
        case ("GET", "/campaigns"):
            (200, campaignsJSON)
        case ("POST", "/campaigns/42/actions/send"):
            (200, #"{"id": 999, "test_url": "https://screen-ide.coderpad.io/?id=999abc"}"#)
        case ("POST", "/campaigns/43/actions/send"):
            (200, #"{"test_url": "https://screen-ide.coderpad.io/?id=no-session-id"}"#)
        case ("GET", "/tests"):
            (200, testsBody(query: query))
        case ("GET", "/tests/13188658"):
            (200, completedTestJSON)
        case ("GET", "/tests/999999"):
            (451, #"{"message":"# + String(repeating: "x", count: 50000) + #""}"#)
        case ("POST", "/tests/13188658/actions/cancel"),
             ("POST", "/tests/13188658/actions/resend"),
             ("DELETE", "/tests/13188658"):
            (204, "")
        case ("GET", "/tests/13188658/report"):
            (200, "%PDF-1.4 mock report bytes")
        case ("GET", "/tests/424242/report"):
            (200, #"{"code": "SomethingElse", "message": "an HTML-ish body, not a PDF"}"#)
        case ("GET", "/webhook"):
            (200, #"{"url": "https://example.com/hook"}"#)
        case ("POST", "/webhook"), ("DELETE", "/webhook"):
            (204, "")
        default:
            (404, #"{"code": "NotFound", "message": "No such resource"}"#)
        }
    }

    /// Routes `GET /tests` fixtures by query: the malformed page, the pagination
    /// edge cases (#857/#858/#898), and the standard two-page listing.
    private static func testsBody(query: [String: String]) -> String {
        switch (query["candidateEmail"], query["campaignId"], query["start"]) {
        case ("malformed@example.com", _, _):
            malformedTestsPageJSON
        // A next_start cycle (nil -> 2 -> 0 -> 2 ...) that must not loop forever (#857).
        case (_, "666", "2"):
            cyclePageBJSON
        case (_, "666", _):
            cyclePageAJSON
        // has_more_items with no usable next_start (#858).
        case (_, "555", _):
            invalidNextPageJSON
        // A session re-served on the second page after an offset shift (#898).
        case (_, "777", "2"):
            dupPage2JSON
        case (_, "777", _):
            dupPage1JSON
        default:
            // Paginate by `start`: page 1 has two of three tests, page 2 the last.
            query["start"] == "2" ? testsPage2JSON : testsPage1JSON
        }
    }

    private static let campaignsJSON = #"""
    [
      {"id": 42, "name": "Backend Screen", "languages": ["java", "python"], "pinned": true, "archived": false},
      {"id": "broken", "name": 7},
      {"id": 43, "name": "Frontend Screen", "languages": ["javascript"], "pinned": false, "archived": true}
    ]
    """#

    private static let cyclePageAJSON = #"""
    {
      "tests": [{"status": "waiting", "id": 10, "id_test": 10, "campaign_id": 666, "tags": [], "questions": []}],
      "pagination": {"start": 0, "limit": 1, "total": 2, "has_more_items": true, "next_start": 2}
    }
    """#

    private static let cyclePageBJSON = #"""
    {
      "tests": [{"status": "waiting", "id": 11, "id_test": 11, "campaign_id": 666, "tags": [], "questions": []}],
      "pagination": {"start": 2, "limit": 1, "total": 2, "has_more_items": true, "next_start": 0}
    }
    """#

    private static let invalidNextPageJSON = #"""
    {
      "tests": [{"status": "waiting", "id": 20, "id_test": 20, "campaign_id": 555, "tags": [], "questions": []}],
      "pagination": {"start": 0, "limit": 1, "total": 5, "has_more_items": true, "next_start": null}
    }
    """#

    private static let dupPage1JSON = #"""
    {
      "tests": [
        {"status": "waiting", "id": 30, "id_test": 30, "campaign_id": 777, "tags": [], "questions": []},
        {"status": "waiting", "id": 31, "id_test": 31, "campaign_id": 777, "tags": [], "questions": []}
      ],
      "pagination": {"start": 0, "limit": 2, "total": 3, "has_more_items": true, "next_start": 2}
    }
    """#

    private static let dupPage2JSON = #"""
    {
      "tests": [
        {"status": "waiting", "id": 31, "id_test": 31, "campaign_id": 777, "tags": [], "questions": []},
        {"status": "waiting", "id": 32, "id_test": 32, "campaign_id": 777, "tags": [], "questions": []}
      ],
      "pagination": {"start": 2, "limit": 2, "total": 3, "has_more_items": false, "next_start": null}
    }
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
final nonisolated class ScreenAPIUnauthorizedMockURLProtocol: URLProtocol {
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

func screenClient(_ proto: URLProtocol.Type = ScreenAPIMockURLProtocol.self,
                  apiKey: String = "test-key") -> ScreenClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [proto]
    return ScreenClient(apiKey: apiKey, session: URLSession(configuration: config))
}
