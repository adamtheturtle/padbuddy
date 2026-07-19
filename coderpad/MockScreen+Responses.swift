//
//  MockScreen+Responses.swift
//  coderpad
//
//  The fake Screen API's request router and its per-resource handlers. Split out of
//  MockScreen.swift so each file stays within the line and body-length limits. Mirrors
//  MockResponses, but Screen returns top-level arrays (not `{ "pads": [...] }`-style
//  envelopes), 204s for its action endpoints, and PDF bytes for reports.
//

import Foundation
import Synchronization

nonisolated enum MockScreenResponses {
    /// A canned response: a status, body bytes, and the `Content-Type` to send (JSON for
    /// most routes, `application/pdf` for the report download).
    struct Result {
        let status: Int
        let body: Data
        let contentType: String
    }

    /// All Screen endpoints live under this versioned prefix (see `ScreenClient`). The
    /// router strips it before matching, so the handlers read clean paths.
    private static let apiPrefix = "/assessment/api/v1.1"

    // Compile the fixed route grammar once. `respond` runs while the mock state's
    // lock is held, so compiling up to six regexes per request serialized every
    // concurrent demo Screen call behind expensive Foundation setup (#2114).
    private static let campaignSendRoute = regex(#"^/campaigns/(\d+)/actions/send/?$"#)
    private static let testReportRoute = regex(#"^/tests/(\d+)/report/?$"#)
    private static let testCancelRoute = regex(#"^/tests/(\d+)/actions/cancel/?$"#)
    private static let testResendRoute = regex(#"^/tests/(\d+)/actions/resend/?$"#)
    private static let testDetailRoute = regex(#"^/tests/(\d+)/?$"#)

    static func respond(
        state: MockScreenState,
        method: String,
        path: String,
        query: [String: String] = [:],
        body: Data? = nil
    ) -> Result {
        // Hold this state's lock so its mutable collections are never read or written by
        // two requests at once: `startLoading()` runs on the URL loading system's
        // background threads. Per-state, so different keys never contend.
        state.lock.withLock { _ in
            respondLocked(state: state, method: method, path: path, query: query, body: body)
        }
    }

    /// The request handler proper. Always invoked while `state.lock` is held, so it may
    /// touch the mutable state without further synchronization. Must not re-enter
    /// `respond` — `Mutex` is not reentrant.
    private static func respondLocked(
        state: MockScreenState,
        method: String,
        path: String,
        query: [String: String],
        body: Data?
    ) -> Result {
        let route = path.hasPrefix(apiPrefix) ? String(path.dropFirst(apiPrefix.count)) : path

        if let result = campaignRoute(state: state, method: method, route: route, body: body) {
            return result
        }
        if let result = testRoute(state: state, method: method, route: route, query: query) {
            return result
        }
        if let result = webhookRoute(state: state, method: method, route: route, body: body) {
            return result
        }
        return json(404, ["code": "not_found", "message": "not handled by mock: \(method) \(route)"])
    }

    // MARK: - Campaign routes

    private static func campaignRoute(
        state: MockScreenState,
        method: String,
        route: String,
        body: Data?
    ) -> Result? {
        if method == "POST",
           let id = match(route, campaignSendRoute),
           let campaignID = Int(id) {
            return sendInvitation(state: state, campaignID: campaignID, body: body)
        }

        if method == "GET", route == "/campaigns" || route == "/campaigns/" {
            return json(200, MockScreenFixtures.campaigns())
        }

        return nil
    }

    /// Creates a "waiting" session from the invitation body and returns the new test id
    /// and the candidate's link, matching `POST /campaigns/:id/actions/send`.
    private static func sendInvitation(state: MockScreenState, campaignID: Int, body: Data?) -> Result {
        let params = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
        let id = state.nextTestID
        state.nextTestID += 1
        let testURL = "https://app.coderpad.io/screen/demo/tests/\(id)"

        var session: [String: Any] = [
            "id": id, "id_test": id, "status": "waiting", "campaign_id": campaignID,
            "organization_id": "demo-org", "candidate_language": "en",
            "send_time": MockScreenFixtures.nowMillis(),
            "last_activity_time": MockScreenFixtures.nowMillis(),
            "url": "https://app.coderpad.io/screen/demo/dashboard/tests/\(id)",
            "test_url": testURL, "questions": []
        ]
        session["candidate_email"] = params["candidate_email"] ?? NSNull()
        session["candidate_name"] = params["candidate_name"] ?? NSNull()
        session["tags"] = (params["tags"] as? String).map(splitTags) ?? []
        state.createdTests.append(session)

        return json(200, ["id": id, "test_url": testURL])
    }

    // MARK: - Test-session routes

    private static func testRoute(
        state: MockScreenState,
        method: String,
        route: String,
        query: [String: String]
    ) -> Result? {
        if method == "GET", let id = match(route, testReportRoute), let testID = Int(id) {
            return reportPDF(state: state, id: testID)
        }
        if method == "POST", let id = match(route, testCancelRoute), let testID = Int(id) {
            state.cancelledTestIDs.insert(testID)
            return noContent()
        }
        if method == "POST", match(route, testResendRoute) != nil {
            // Resending just re-emails the invitation; nothing in the mock changes.
            return noContent()
        }
        if method == "DELETE", let id = match(route, testDetailRoute), let testID = Int(id) {
            state.deletedTestIDs.insert(testID)
            return noContent()
        }
        if method == "GET", let id = match(route, testDetailRoute), let testID = Int(id) {
            return singleTest(state: state, id: testID, query: query)
        }
        if method == "GET", route == "/tests" || route == "/tests/" {
            return testsPage(state: state, query: query)
        }

        return nil
    }

    /// One page of sessions for `GET /tests`, honoring the `campaignId`/`candidateEmail`
    /// filters, the `from`/`to` epoch-millisecond activity bounds (the Date Range picker,
    /// #999), and `start`/`limit` offset pagination.
    private static func testsPage(state: MockScreenState, query: [String: String]) -> Result {
        var tests = state.allTests()
        if let campaignID = query["campaignId"].flatMap(Int.init) {
            tests = tests.filter { ($0["campaign_id"] as? Int) == campaignID }
        }
        if let email = query["candidateEmail"] {
            tests = tests.filter { ($0["candidate_email"] as? String) == email }
        }
        // Mirror the live API's date bounds: a session is in range by its activity
        // timestamp (falling back to send time). Without this the Demo account's
        // Date Range picker silently did nothing (#999).
        if let fromMillis = query["from"].flatMap(Int.init) {
            tests = tests.filter { activityMillis($0) >= fromMillis }
        }
        if let toMillis = query["to"].flatMap(Int.init) {
            tests = tests.filter { activityMillis($0) <= toMillis }
        }

        let total = tests.count
        let start = max(query["start"].flatMap(Int.init) ?? 0, 0)
        let limit = max(query["limit"].flatMap(Int.init) ?? total, 0)
        let end = min(start + limit, total)
        let window = start < end ? Array(tests[start ..< end]) : []
        let hasMore = end < total

        var pagination: [String: Any] = [
            "start": start, "limit": limit, "total": total, "has_more_items": hasMore
        ]
        if hasMore { pagination["next_start"] = end }
        return json(200, ["tests": window, "pagination": pagination])
    }

    /// A session's activity instant in epoch milliseconds, for the `from`/`to` bounds:
    /// `last_activity_time` first, then `send_time`, matching the fixtures' fields.
    private static func activityMillis(_ test: [String: Any]) -> Int {
        (test["last_activity_time"] as? Int) ?? (test["send_time"] as? Int) ?? 0
    }

    /// A single session for `GET /tests/:id`. Drops the report's community-score buckets
    /// unless `withCommunityStats=true`, mirroring the live API's opt-in field.
    private static func singleTest(state: MockScreenState, id: Int, query: [String: String]) -> Result {
        guard var test = state.allTests().first(where: { ($0["id"] as? Int) == id }) else {
            return json(404, ["code": "not_found", "message": "test not found"])
        }

        if query["withCommunityStats"] != "true", var report = test["report"] as? [String: Any] {
            report["community_stats"] = nil
            test["report"] = report
        }
        return json(200, test)
    }

    /// The candidate's report as PDF bytes for `GET /tests/:id/report`.
    private static func reportPDF(state: MockScreenState, id: Int) -> Result {
        guard let test = state.allTests().first(where: { ($0["id"] as? Int) == id }) else {
            return json(404, ["code": "not_found", "message": "test not found"])
        }

        let candidate = (test["candidate_name"] as? String)
            ?? (test["candidate_email"] as? String) ?? "Candidate"
        let score = (test["report"] as? [String: Any])?["score"] as? Double
        let data = MockScreenFixtures.reportPDF(candidate: candidate, score: score)
        return Result(status: 200, body: data, contentType: "application/pdf")
    }

    // MARK: - Webhook routes

    private static func webhookRoute(
        state: MockScreenState,
        method: String,
        route: String,
        body: Data?
    ) -> Result? {
        guard route == "/webhook" || route == "/webhook/" else { return nil }

        switch method {
        case "GET":
            return json(200, ["url": (state.webhookURL as Any?) ?? NSNull()])

        case "POST":
            // The body is the URL as a bare JSON string, per the API contract.
            if let body, let url = try? JSONDecoder().decode(String.self, from: body) {
                state.webhookURL = url
            }
            return noContent()

        case "DELETE":
            state.webhookURL = nil
            return noContent()

        default:
            return nil
        }
    }

    // MARK: - Helpers

    private static func json(_ status: Int, _ value: Any) -> Result {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]))
            ?? Data("{}".utf8)
        return Result(status: status, body: data, contentType: "application/json")
    }

    /// The 204 No Content used by the action and webhook write endpoints.
    private static func noContent() -> Result {
        Result(status: 204, body: Data(), contentType: "application/json")
    }

    /// Splits an invitation's comma-separated `tags` string into the array shape the
    /// session model exposes.
    private static func splitTags(_ tags: String) -> [String] {
        tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func match(_ path: String, _ regex: NSRegularExpression) -> String? {
        let range = NSRange(path.startIndex..., in: path)
        guard let match = regex.firstMatch(in: path, range: range),
              match.numberOfRanges >= 2,
              let captured = Range(match.range(at: 1), in: path) else { return nil }

        return String(path[captured])
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("Invalid built-in mock route: \(pattern)")
        }
    }
}
