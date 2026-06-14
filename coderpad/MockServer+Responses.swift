//
//  MockServer+Responses.swift
//  coderpad
//
//  The fake API's request router and its per-resource handlers. Split out of
//  MockServer.swift so each file stays within the line and body-length limits.
//

import Foundation
import Synchronization

nonisolated enum MockResponses {
    static func respond(
        state: MockState,
        method: String,
        path: String,
        query: [String: String] = [:],
        body: Data?
    ) -> (Int, Data) {
        // Hold this state's lock so its mutable collections are never read or
        // written by two requests at once. `startLoading()` on the backing
        // `URLProtocol` runs on the URL loading system's background threads, and the
        // client fans pages out concurrently. The lock is per-state, so requests
        // against different keys (e.g. parallel tests) never contend.
        state.lock.withLock { _ in
            respondLocked(state: state, method: method, path: path, query: query, body: body)
        }
    }

    /// The request handler proper. Always invoked while `state.lock` is held, so it
    /// (and the `MockState` accessors it calls) may touch the mutable state without
    /// further synchronization. Must not re-enter `respond` — `Mutex` is not reentrant.
    private static func respondLocked(
        state: MockState,
        method: String,
        path: String,
        query: [String: String] = [:],
        body: Data?
    ) -> (Int, Data) {
        if let result = padRoute(state: state, method: method, path: path, body: body) {
            return result
        }
        if let result = questionRoute(state: state, method: method, path: path, body: body) {
            return result
        }
        if let result = organizationRoute(state: state, method: method, path: path, query: query) {
            return result
        }
        return (404, jsonString(["status": "error", "message": "not handled by mock: \(method) \(path)"]))
    }

    // MARK: - Pad routes

    private static func padRoute(state: MockState, method: String, path: String, body: Data?) -> (Int, Data)? {
        // Modify a pad: the live API carries the pad id in the URL path
        // (`PUT /api/pads/:id`), with the changed attributes in the body.
        if method == "PUT", let id = match(path, pattern: #"^/api/pads/([^/]+)/?$"#), !id.isEmpty {
            return modifyPad(state: state, id: id, body: body)
        }

        if method == "POST", path == "/api/pads/" || path == "/api/pads" {
            return createPad(state: state, body: body)
        }

        if method == "GET", let id = match(path, pattern: #"^/api/pads/([^/]+)/events/?$"#), !id.isEmpty {
            // Mirror the single-pad route: an events request for a pad that doesn't
            // exist (or was deleted) is a 404, not a canned timeline.
            guard state.allPads().contains(where: { ($0["id"] as? String) == id }) else {
                return (404, jsonString(["status": "error", "message": "pad not found"]))
            }
            return ok([
                "status": "OK",
                "events": MockFixtures.events(forPad: id)
            ])
        }

        if method == "GET", let id = match(path, pattern: #"^/api/pads/([^/]+)/?$"#), !id.isEmpty {
            if var pad = state.allPads().first(where: { ($0["id"] as? String) == id }) {
                // Mirror the live API: the pad's fields are returned flat at the top level.
                pad["status"] = "OK"
                return ok(pad)
            }
            return (404, jsonString(["status": "error", "message": "pad not found"]))
        }

        if method == "GET", path == "/api/pads/" || path == "/api/pads" {
            return ok(["status": "OK", "pads": state.allPads()])
        }

        if method == "GET", let id = match(path, pattern: #"^/api/pad_environments/(\d+)/?$"#) {
            let idInt = Int(id) ?? 1
            // Mirror the live API: the environment's fields are returned flat.
            var env = MockFixtures.padEnvironment(id: idInt)
            env["status"] = "OK"
            return ok(env)
        }

        return nil
    }

    private static func modifyPad(state: MockState, id: String, body: Data?) -> (Int, Data) {
        var dict = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
        // The live API mirrors `deleted`/`ended` as side effects, not stored fields.
        if dict["deleted"] as? Bool == true {
            state.deletedPadIDs.insert(id)
            return (200, jsonString(["status": "OK"]))
        }
        if dict["ended"] as? Bool == true {
            dict["state"] = "ended"
            dict["ended_at"] = Date.now.formatted(.iso8601)
        }
        // The create/modify API takes a singular `question_id`; the pad body
        // exposes it as the `question_ids` array, so mirror it on merge.
        if let questionID = dict.removeValue(forKey: "question_id") {
            dict["question_ids"] = [questionID]
        }
        state.updatedPads[id] = dict
        // Mirror the live API: PUT returns only a status, not the pad body.
        if state.allPads().contains(where: { ($0["id"] as? String) == id }) {
            return ok(["status": "OK"])
        }
        return (404, jsonString(["status": "error", "message": "pad not found"]))
    }

    private static func createPad(state: MockState, body: Data?) -> (Int, Data) {
        let create = (try? JSONDecoder().decode(PadCreate.self, from: body ?? Data())) ?? PadCreate()
        let id = "DEMO\(Int.random(in: 1000 ... 9999))"
        var pad = MockFixtures.pad(
            id: id,
            title: create.title ?? "Demo Pad \(id)",
            language: create.language ?? "python3",
            ownerEmail: create.ownerEmail ?? "demo@example.com",
            state: "started",
            isPrivate: create.isPrivate ?? false,
            executionEnabled: create.executionEnabled ?? true
        )
        // Reflect the documented create params back into the pad body.
        pad["question_ids"] = create.questionID.map { [$0] } ?? []
        if let teamID = create.teamID {
            pad["team"] = ["id": teamID, "name": teamID]
        }
        state.createdPads.append(pad)
        // Mirror the live API: the created pad is returned flat at the top level.
        var response = pad
        response["status"] = "OK"
        return ok(response)
    }

    // MARK: - Question routes

    private static func questionRoute(state: MockState, method: String, path: String, body: Data?) -> (Int, Data)? {
        if method == "POST", path == "/api/questions/" || path == "/api/questions" {
            return createQuestion(state: state, body: body)
        }

        if method == "PUT", let id = match(path, pattern: #"^/api/questions/(\d+)/?$"#) {
            return modifyQuestion(state: state, idInt: Int(id) ?? 0, body: body)
        }

        if method == "DELETE", let id = match(path, pattern: #"^/api/questions/(\d+)/?$"#) {
            let idInt = Int(id) ?? 0
            state.deletedQuestionIDs.insert(idInt)
            return (200, jsonString(["status": "OK"]))
        }

        if method == "GET", let id = match(path, pattern: #"^/api/questions/(\d+)/?$"#) {
            let idInt = Int(id) ?? 0
            if var question = state.allQuestions().first(where: { ($0["id"] as? Int) == idInt }) {
                // Mirror the live API: the question's fields are returned flat.
                question["status"] = "OK"
                return ok(question)
            }
            return (404, jsonString(["status": "error"]))
        }

        if method == "GET", path == "/api/questions/" || path == "/api/questions" {
            return ok(["status": "OK", "questions": state.allQuestions()])
        }

        return nil
    }

    private static func createQuestion(state: MockState, body: Data?) -> (Int, Data) {
        let bodyDict = flattenQuestionParams(
            (try? JSONSerialization.jsonObject(with: body ?? Data()) as? [String: Any]) ?? [:]
        )
        let newID = (MockFixtures.questions().compactMap { $0["id"] as? Int }.max() ?? 100) + 1
        var question: [String: Any] = [
            "id": newID,
            "title": bodyDict["title"] as? String ?? "Untitled",
            "owner_email": "demo@example.com",
            "language": bodyDict["language"] ?? NSNull(),
            "description": bodyDict["description"] ?? NSNull(),
            "candidate_instructions": bodyDict["candidate_instructions"] ?? [],
            "shared": false, "used": 0, "take_home": bodyDict["take_home"] as? Bool ?? false,
            "test_cases_enabled": false, "solution": bodyDict["solution"] ?? "",
            "pad_type": bodyDict["pad_type"] as? String ?? "live", "is_draft": true,
            "contents": bodyDict["contents"] ?? NSNull(), "custom_files": [],
            "author_name": "Demo User", "organization_name": "Demo Org",
            "created_at": Date.now.formatted(.iso8601),
            "updated_at": Date.now.formatted(.iso8601)
        ]
        state.createdQuestions.append(question)
        // Mirror the live API: the question's fields are returned flat at the top level.
        question["status"] = "OK"
        return ok(question)
    }

    private static func modifyQuestion(state: MockState, idInt: Int, body: Data?) -> (Int, Data) {
        guard let body,
              let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            return (400, jsonString(["status": "error"]))
        }
        state.updatedQuestions[idInt] = flattenQuestionParams(dict)
        // Mirror the live API: PUT returns only a status, not the question body.
        if state.allQuestions().contains(where: { ($0["id"] as? Int) == idInt }) {
            return ok(["status": "OK"])
        }
        return (404, jsonString(["status": "error"]))
    }

    // MARK: - Organization routes

    private static func organizationRoute(
        state: MockState,
        method: String,
        path: String,
        query: [String: String]
    ) -> (Int, Data)? {
        if method == "GET", path == "/api/quota" {
            return ok(MockFixtures.quota())
        }

        if method == "GET", path == "/api/organization" {
            return ok(MockFixtures.organization())
        }

        if method == "GET", path == "/api/organization/stats" {
            return ok(MockFixtures.organizationStats(query: query))
        }

        if method == "GET", path == "/api/organization/pads" {
            return ok(["status": "OK", "pads": state.allPads()])
        }

        if method == "GET", path == "/api/organization/questions" {
            return ok(["status": "OK", "questions": state.allQuestions()])
        }

        if method == "GET", path == "/api/organization/users" {
            let users = MockFixtures.users()
            if let email = query["email"] {
                return ok(["status": "OK", "users": users.filter { ($0["email"] as? String) == email }])
            }
            return ok(["status": "OK", "users": users])
        }

        return nil
    }

    // MARK: - Helpers

    private static func ok(_ value: Any) -> (Int, Data) {
        (200, jsonString(value))
    }

    private static func jsonString(_ value: Any) -> Data {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]) {
            return data
        }
        return Data("{}".utf8)
    }

    /// The question create/modify API nests `title`/`language` under a `question`
    /// object (`question[title]`). Lift those back to top level so the fixtures,
    /// which store flat keys, can read them — with a flat fallback for older callers.
    private static func flattenQuestionParams(_ dict: [String: Any]) -> [String: Any] {
        guard let nested = dict["question"] as? [String: Any] else { return dict }
        var flattened = dict
        flattened.removeValue(forKey: "question")
        for (key, value) in nested {
            flattened[key] = value
        }
        return flattened
    }

    private static func match(_ path: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(path.startIndex..., in: path)
        guard let match = regex.firstMatch(in: path, range: range),
              match.numberOfRanges >= 2,
              let captured = Range(match.range(at: 1), in: path) else { return nil }
        return String(path[captured])
    }
}
