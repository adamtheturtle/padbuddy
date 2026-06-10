//
//  MockServer.swift
//  coderpad
//
//  In-process URLProtocol that fakes the CoderPad API with canned data,
//  so the app can run in a demo mode without a real key or network.
//

import Foundation

enum MockServer {
    static let host = "app.coderpad.io"

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self] + (config.protocolClasses ?? [])
        return URLSession(configuration: config)
    }
}

final class MockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == MockServer.host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let path = url.path
        let method = request.httpMethod ?? "GET"
        let bodyData = request.httpBody ?? Self.drain(stream: request.httpBodyStream)

        let (status, body) = MockResponses.respond(method: method, path: path, body: bodyData)

        let headers = ["Content-Type": "application/json"]
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func drain(stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

enum MockResponses {
    static func respond(method: String, path: String, body: Data?) -> (Int, Data) {
        if method == "PUT", path == "/api/pads/" || path == "/api/pads" {
            guard let body,
                  let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let id = dict["id"] as? String else {
                return (400, jsonString(["status": "error", "message": "missing id"]))
            }
            MockFixtures.updatedPads[id] = dict
            if let pad = MockFixtures.allPads().first(where: { ($0["id"] as? String) == id }) {
                return ok(["status": "OK", "pad": pad])
            }
            return (404, jsonString(["status": "error", "message": "pad not found"]))
        }

        if method == "POST", path == "/api/pads/" || path == "/api/pads" {
            let create = (try? JSONDecoder().decode(PadCreate.self, from: body ?? Data())) ?? PadCreate()
            let id = "DEMO\(Int.random(in: 1000...9999))"
            let pad = MockFixtures.pad(
                id: id,
                title: create.title ?? "Demo Pad \(id)",
                language: create.language ?? "python3",
                ownerEmail: create.ownerEmail ?? "demo@example.com",
                state: "started",
                isPrivate: create.isPrivate ?? false,
                executionEnabled: create.executionEnabled ?? true
            )
            MockFixtures.createdPads.append(pad)
            return ok(["status": "OK", "pad": pad])
        }

        if method == "GET", let id = match(path, pattern: #"^/api/pads/([^/]+)/events/?$"#) {
            return ok([
                "status": "OK",
                "events": MockFixtures.events(forPad: id)
            ])
        }

        if method == "GET", let id = match(path, pattern: #"^/api/pads/([^/]+)/?$"#), !id.isEmpty {
            if let pad = MockFixtures.allPads().first(where: { ($0["id"] as? String) == id }) {
                return ok(["status": "OK", "pad": pad])
            }
            return (404, jsonString(["status": "error", "message": "pad not found"]))
        }

        if method == "GET", path == "/api/pads/" || path == "/api/pads" {
            return ok(["status": "OK", "pads": MockFixtures.allPads()])
        }

        if method == "GET", let id = match(path, pattern: #"^/api/pad_environments/(\d+)/?$"#) {
            let idInt = Int(id) ?? 1
            return ok(["status": "OK", "pad_environment": MockFixtures.padEnvironment(id: idInt)])
        }

        if method == "POST", path == "/api/questions/" || path == "/api/questions" {
            let bodyDict = (try? JSONSerialization.jsonObject(with: body ?? Data()) as? [String: Any]) ?? [:]
            let newID = (MockFixtures.questions().compactMap { $0["id"] as? Int }.max() ?? 100) + 1
            var q: [String: Any] = [
                "id": newID,
                "title": bodyDict["title"] as? String ?? "Untitled",
                "owner_email": "demo@example.com",
                "language": bodyDict["language"] ?? NSNull(),
                "description": bodyDict["description"] ?? NSNull(),
                "candidate_instructions": bodyDict["candidate_instructions"] ?? [],
                "shared": false, "used": 0, "take_home": bodyDict["take_home"] as? Bool ?? false,
                "test_cases_enabled": false, "solution": bodyDict["solution"] ?? "",
                "pad_type": bodyDict["pad_type"] as? String ?? "live", "is_draft": true,
                "author_name": "Demo User", "organization_name": "Demo Org",
                "created_at": ISO8601DateFormatter().string(from: Date()),
                "updated_at": ISO8601DateFormatter().string(from: Date()),
            ]
            MockFixtures.createdQuestions.append(q)
            return ok(["status": "OK", "question": q])
        }

        if method == "PUT", let id = match(path, pattern: #"^/api/questions/(\d+)/?$"#) {
            let idInt = Int(id) ?? 0
            guard let body,
                  let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                return (400, jsonString(["status": "error"]))
            }
            MockFixtures.updatedQuestions[idInt] = dict
            if let q = MockFixtures.allQuestions().first(where: { ($0["id"] as? Int) == idInt }) {
                return ok(["status": "OK", "question": q])
            }
            return (404, jsonString(["status": "error"]))
        }

        if method == "DELETE", let id = match(path, pattern: #"^/api/questions/(\d+)/?$"#) {
            let idInt = Int(id) ?? 0
            MockFixtures.deletedQuestionIDs.insert(idInt)
            return (200, jsonString(["status": "OK"]))
        }

        if method == "GET", let id = match(path, pattern: #"^/api/questions/(\d+)/?$"#) {
            let idInt = Int(id) ?? 0
            if let q = MockFixtures.allQuestions().first(where: { ($0["id"] as? Int) == idInt }) {
                return ok(["status": "OK", "question": q])
            }
            return (404, jsonString(["status": "error"]))
        }

        if method == "GET", path == "/api/questions/" || path == "/api/questions" {
            return ok(["status": "OK", "questions": MockFixtures.allQuestions()])
        }

        if method == "GET", path == "/api/quota" {
            return ok(MockFixtures.quota())
        }

        if method == "GET", path == "/api/organization" {
            return ok(MockFixtures.organization())
        }

        if method == "GET", path == "/api/organization/stats" {
            return ok(MockFixtures.organizationStats())
        }

        if method == "GET", path == "/api/organization/pads" {
            return ok(["status": "OK", "pads": MockFixtures.allPads()])
        }

        if method == "GET", path == "/api/organization/questions" {
            return ok(["status": "OK", "questions": MockFixtures.questions()])
        }

        if method == "GET", path == "/api/organization/users" {
            return ok(["status": "OK", "users": MockFixtures.users()])
        }

        return (404, jsonString(["status": "error", "message": "not handled by mock: \(method) \(path)"]))
    }

    private static func ok(_ value: Any) -> (Int, Data) {
        (200, jsonString(value))
    }

    private static func jsonString(_ value: Any) -> Data {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]) {
            return data
        }
        return Data("{}".utf8)
    }

    private static func match(_ path: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(path.startIndex..., in: path)
        guard let match = regex.firstMatch(in: path, range: range),
              match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: path) else { return nil }
        return String(path[r])
    }
}

enum MockFixtures {
    nonisolated(unsafe) static var createdPads: [[String: Any]] = []
    nonisolated(unsafe) static var updatedPads: [String: [String: Any]] = [:]
    nonisolated(unsafe) static var createdQuestions: [[String: Any]] = []
    nonisolated(unsafe) static var updatedQuestions: [Int: [String: Any]] = [:]
    nonisolated(unsafe) static var deletedQuestionIDs: Set<Int> = []

    static func allQuestions() -> [[String: Any]] {
        let merged = questions().map { q -> [String: Any] in
            guard let id = q["id"] as? Int, let updates = updatedQuestions[id] else { return q }
            var m = q
            for (k, v) in updates where k != "id" { m[k] = v }
            return m
        }
        return (merged + createdQuestions).filter { q in
            guard let id = q["id"] as? Int else { return true }
            return !deletedQuestionIDs.contains(id)
        }
    }

    static func allPads() -> [[String: Any]] {
        let base = seedPads().map { pad -> [String: Any] in
            guard let id = pad["id"] as? String, let updates = updatedPads[id] else { return pad }
            var merged = pad
            for (key, value) in updates where key != "id" { merged[key] = value }
            return merged
        }
        return base + createdPads
    }

    private static func seedPads() -> [[String: Any]] {
        [
            pad(id: "DEMOABC1", title: "Onsite — Jane Doe",
                language: "python3", ownerEmail: "alex@demo.co",
                state: "started", isPrivate: false, executionEnabled: true,
                participants: ["Jane Doe", "Alex Park"],
                createdAt: "2026-06-08T15:00:00Z", updatedAt: "2026-06-09T22:00:00Z"),
            pad(id: "DEMOXYZ2", title: "Phone screen — Sam Lee",
                language: "javascript", ownerEmail: "morgan@demo.co",
                state: "ended", isPrivate: true, executionEnabled: true,
                participants: ["Sam Lee", "Morgan Lin"],
                createdAt: "2026-06-05T17:30:00Z", updatedAt: "2026-06-06T19:00:00Z",
                endedAt: "2026-06-06T19:00:00Z"),
            pad(id: "DEMOPLY3", title: "Live coding — backend",
                language: "go", ownerEmail: "alex@demo.co",
                state: "started", isPrivate: false, executionEnabled: false,
                participants: ["Casey Wu", "Alex Park"],
                createdAt: "2026-06-09T18:00:00Z", updatedAt: "2026-06-09T18:20:00Z"),
            pad(id: "DEMOOLD4", title: "Q1 take-home draft",
                language: "rust", ownerEmail: "morgan@demo.co",
                state: "draft", isPrivate: true, executionEnabled: true,
                participants: [],
                createdAt: "2026-05-12T10:00:00Z", updatedAt: "2026-05-12T10:00:00Z"),
            pad(id: "DEMOSWFT5", title: "iOS sample pad",
                language: "swift", ownerEmail: "demo@example.com",
                state: "started", isPrivate: false, executionEnabled: true,
                participants: ["Demo User"],
                createdAt: "2026-06-09T09:00:00Z", updatedAt: "2026-06-10T08:00:00Z"),
        ]
    }

    static func pad(id: String,
                    title: String,
                    language: String,
                    ownerEmail: String,
                    state: String,
                    isPrivate: Bool = false,
                    executionEnabled: Bool = true,
                    participants: [String] = [],
                    createdAt: String = "2026-06-10T08:00:00Z",
                    updatedAt: String = "2026-06-10T08:00:00Z",
                    endedAt: String? = nil) -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "title": title,
            "state": state,
            "owner_email": ownerEmail,
            "language": language,
            "private": isPrivate,
            "execution_enabled": executionEnabled,
            "participants": participants,
            "url": "https://app.coderpad.io/\(id)",
            "playback": "https://app.coderpad.io/\(id)/playback",
            "created_at": createdAt,
            "updated_at": updatedAt,
            "type": "live",
            "active_environment_id": 1,
            "pad_environment_ids": [1, 2],
            "question_ids": [101],
            "team": ["id": "demo-team", "name": "Demo Team"]
        ]
        if let endedAt { dict["ended_at"] = endedAt } else { dict["ended_at"] = NSNull() }
        return dict
    }

    static func events(forPad id: String) -> [[String: Any]] {
        [
            ["message": "Pad started", "kind": "started",
             "user_name": "Alex Park", "user_email": "alex@demo.co",
             "created_at": "2026-06-09T18:00:00Z"],
            ["message": "Jane Doe joined the pad", "kind": "joined",
             "user_name": "Jane Doe", "user_email": NSNull(),
             "created_at": "2026-06-09T18:01:42Z"],
            ["message": "Code executed", "kind": "ran",
             "user_name": "Jane Doe", "user_email": NSNull(),
             "created_at": "2026-06-09T18:14:08Z"],
            ["message": "Jane Doe left the pad", "kind": "left",
             "user_name": "Jane Doe", "user_email": NSNull(),
             "created_at": "2026-06-09T18:46:20Z"],
        ]
    }

    static func padEnvironment(id: Int) -> [String: Any] {
        [
            "id": id,
            "title": id == 1 ? "Main" : "Scratch",
            "language": id == 1 ? "python3" : "javascript",
            "contents": "# demo contents",
            "created_at": "2026-06-09T18:00:00Z",
            "updated_at": "2026-06-09T18:00:00Z",
        ]
    }

    static func questions() -> [[String: Any]] {
        [
            [
                "id": 101,
                "title": "FizzBuzz",
                "owner_email": "alex@demo.co",
                "language": "python3",
                "description": "Classic warm-up problem.",
                "candidate_instructions": [["instructions": "Print numbers 1–100 with Fizz/Buzz rules.", "default_visible": true]],
                "shared": true, "used": 42, "take_home": false,
                "test_cases_enabled": true, "solution": "see notion",
                "pad_type": "live", "is_draft": false,
                "author_name": "Alex Park", "organization_name": "Demo Org",
                "created_at": "2025-09-01T10:00:00Z", "updated_at": "2026-06-08T10:00:00Z"
            ],
            [
                "id": 102,
                "title": "URL shortener (take-home)",
                "owner_email": "morgan@demo.co",
                "language": "go",
                "description": "Design and ship a small URL shortener.",
                "candidate_instructions": [["instructions": "Read the spec, scope your solution.", "default_visible": true]],
                "shared": true, "used": 5, "take_home": true,
                "test_cases_enabled": false, "solution": "",
                "pad_type": "take-home", "is_draft": false,
                "author_name": "Morgan Lin", "organization_name": "Demo Org",
                "created_at": "2025-11-12T14:00:00Z", "updated_at": "2026-05-30T09:00:00Z"
            ],
            [
                "id": 103,
                "title": "[DRAFT] Concurrency primitives",
                "owner_email": "alex@demo.co",
                "language": "rust",
                "description": NSNull(),
                "candidate_instructions": [["instructions": "", "default_visible": true]],
                "shared": false, "used": 0, "take_home": false,
                "test_cases_enabled": false, "solution": "",
                "pad_type": "live", "is_draft": true,
                "author_name": "Alex Park", "organization_name": "Demo Org",
                "created_at": "2026-06-05T11:00:00Z", "updated_at": "2026-06-05T11:00:00Z"
            ],
        ]
    }

    static func users() -> [[String: Any]] {
        [
            ["email": "alex@demo.co", "name": "Alex Park",
             "teams": ["demo-team"], "pads_created": 12],
            ["email": "morgan@demo.co", "name": "Morgan Lin",
             "teams": ["demo-team"], "pads_created": 9],
            ["email": "casey@demo.co", "name": "Casey Wu",
             "teams": ["demo-team"], "pads_created": 2],
            ["email": "robin@demo.co", "name": "Robin Patel",
             "teams": ["demo-team"], "pads_created": 0],
            ["email": "demo@example.com", "name": "Demo User",
             "teams": ["demo-team"], "pads_created": 1],
        ]
    }

    static func organization() -> [String: Any] {
        [
            "status": "OK",
            "id": 9999,
            "organization_name": "Demo Org",
            "child_organizations": [],
            "user_count": users().count,
            "users": users(),
            "organization_default_language": "python3",
            "single_sign_on_supported": false,
            "teams": [["id": "demo-team", "name": "Demo Team"]]
        ]
    }

    static func organizationStats() -> [String: Any] {
        [
            "status": "OK",
            "start_time": "2026-06-01T00:00:00.000-07:00",
            "end_time": "2026-06-10T00:00:00.000-07:00",
            "pads_created": 7,
            "users": users()
        ]
    }

    static func quota() -> [String: Any] {
        [
            "status": "OK",
            "trial_expires_at": "2027-01-01T00:00:00.000-08:00",
            "pads_used": 24,
            "quota_reset_at": "2026-07-01T00:00:00.000-07:00",
            "unlimited": false,
            "overages_enabled": true
        ]
    }
}
