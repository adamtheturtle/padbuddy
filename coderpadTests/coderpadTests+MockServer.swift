//
//  coderpadTests+MockServer.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

/// Each test gets its own mock client keyed by a unique API key, so its created /
/// updated / deleted pads land in an isolated `MockState` rather than process-wide
/// storage. With no shared mutable state to race on, the suite runs in parallel
/// (no `.serialized`).
@Suite("Mock server end-to-end")
struct MockServerTests {
    private let client = CoderPadClient.mock(key: "test-\(UUID().uuidString)")

    @Test
    func `listPads returns the seeded pads`() async throws {
        let pads = try await client.listPads()
        #expect(pads.count >= 5)
        #expect(pads.contains(where: { $0.id == "DEMOABC1" }))
        #expect(pads.allSatisfy { !$0.id.isEmpty })
    }

    @Test
    func `listPadsIncrementally yields page 1 first, then the full list`() async throws {
        var snapshots: [[Pad]] = []
        for try await snapshot in client.listPadsIncrementally() {
            snapshots.append(snapshot)
        }
        // At least one snapshot, the first is non-empty (page 1 renders immediately),
        // each snapshot only grows, and the final matches the all-at-once fetch.
        let first = try #require(snapshots.first)
        #expect(!first.isEmpty)
        #expect(zip(snapshots, snapshots.dropFirst()).allSatisfy { $0.count <= $1.count })
        let expected = try await client.listPads(sort: "updated_at,desc")
        #expect(snapshots.last?.map(\.id) == expected.map(\.id))
    }

    @Test
    func `getPad returns a specific pad`() async throws {
        let pad = try await client.getPad(id: "DEMOABC1")
        #expect(pad.title == "Onsite: Jane Doe")
        #expect(pad.ownerEmail == "alex@demo.co")
        #expect(pad.participants == ["Jane Doe", "Alex Park"])
    }

    @Test
    func `a pad exposes its whiteboard drawing URL`() async throws {
        let pad = try await client.getPad(id: "DEMOXYZ2")
        let drawing = try #require(pad.drawing)
        #expect(!drawing.isEmpty)
        #expect(URL(string: drawing) != nil)
        // Pads without a whiteboard decode it as nil rather than an empty string.
        let noDrawing = try await client.getPad(id: "DEMOABC1")
        #expect(noDrawing.drawing == nil)
    }

    @Test
    func `padEvents returns events for a pad`() async throws {
        let events = try await client.padEvents(padID: "DEMOABC1")
        #expect(events.count == 6)
        #expect(events.first?.kind == "started")
        #expect(events.contains(where: { $0.kind == "ran" }))
        #expect(events.contains(where: { $0.kind == "added_question" }))
    }

    @Test
    func `padEvents vary per pad rather than returning one canned list`() async throws {
        let onsite = try await client.padEvents(padID: "DEMOABC1")
        let draft = try await client.padEvents(padID: "DEMOOLD4")
        // The untouched draft has a deliberately thin, distinct timeline.
        #expect(draft.count == 1)
        #expect(draft.count != onsite.count)
        // The ended phone screen reaches a terminal `ended` event.
        let ended = try await client.padEvents(padID: "DEMOXYZ2")
        #expect(ended.contains(where: { $0.kind == "ended" }))
    }

    @Test
    func `padEnvironment returns the requested environment`() async throws {
        let env = try await client.padEnvironment(id: 1)
        #expect(env.id == 1)
        #expect(env.language == "python3")
        #expect(env.fileContents.first?.path == "coderpad/main.py")
        #expect(env.contents?.contains("Hello") == true)
    }

    @Test
    func `listQuestions returns the seeded questions`() async throws {
        let questions = try await client.listQuestions()
        #expect(questions.count == 3)
        #expect(questions.contains(where: { $0.title == "FizzBuzz" }))
    }

    @Test
    func `the seeded FizzBuzz question carries both starter-code variants`() async throws {
        let questions = try await client.listQuestions()
        let fizzBuzz = try #require(questions.first { $0.title == "FizzBuzz" })
        let contents = try #require(fizzBuzz.contents)
        let testContents = try #require(fizzBuzz.contentsForTestCases)
        #expect(!contents.isEmpty)
        #expect(!testContents.isEmpty)
        // The two variants differ, so the question detail shows both starter-code cards.
        #expect(contents != testContents)
    }

    @Test
    func `organization returns the demo org with users`() async throws {
        let org = try await client.organization()
        #expect(org.organizationName == "Demo Org")
        #expect(org.users.count >= 5)
        #expect(org.users.contains(where: { $0.email == "alex@demo.co" }))
        // Backs the org-default language pre-selection in the create sheets.
        #expect(org.organizationDefaultLanguage == "go")
        // Backs the Organization view's single sign-on row and portal action.
        #expect(org.singleSignOnSupported == true)
        #expect(org.singleSignInURL == "https://app.coderpad.io/sso/demo-org")
    }

    @Test
    func `quota returns the demo plan`() async throws {
        let quota = try await client.quota()
        #expect(quota.padsUsed == 24)
        #expect(quota.unlimited == false)
        #expect(quota.overagesEnabled == true)
        #expect(quota.quotaReset != nil)
        #expect(quota.padsRemaining == 96)
        #expect(quota.billingCyclePadLimit == 120)
    }

    @Test
    func `organizationUsers filters by email when provided`() async throws {
        let all = try await client.organizationUsers()
        #expect(all.count >= 5)
        let one = try await client.organizationUsers(email: "alex@demo.co")
        #expect(one.count == 1)
        #expect(one.first?.email == "alex@demo.co")
    }

    @Test
    func `listOrganizationPads and questions return org-wide data`() async throws {
        let pads = try await client.listOrganizationPads()
        #expect(!pads.isEmpty)
        let questions = try await client.listOrganizationQuestions()
        #expect(!questions.isEmpty)
    }

    @Test
    func `endPad marks the pad ended`() async throws {
        // DEMOABC1 is a seeded pad, so the mock's update merge applies; ending only
        // flips state/ended_at, leaving the pad listable for other tests.
        try await client.endPad(id: "DEMOABC1")
        let pad = try await client.getPad(id: "DEMOABC1")
        #expect(pad.state == "ended")
        #expect(pad.endedAt != nil)
    }

    @Test
    func `deletePad removes a created pad from listings`() async throws {
        // Delete a freshly created pad rather than a seed, so the suite's
        // "listPads returns the seeded pads" invariant is unaffected.
        let new = try await client.createPad(PadCreate(title: "To delete"))
        try await client.deletePad(id: new.id)
        let after = try await client.listPads()
        #expect(!after.contains(where: { $0.id == new.id }))
    }

    @Test
    func `createPad echoes a new pad and makes it listable`() async throws {
        let before = try await client.listPads()
        let new = try await client.createPad(PadCreate(
            title: "Created via mock",
            language: "swift",
            ownerEmail: "demo@example.com",
            isPrivate: false,
            executionEnabled: true
        ))
        #expect(new.title == "Created via mock")
        #expect(new.language == "swift")
        let after = try await client.listPads()
        #expect(after.count == before.count + 1)
        #expect(after.contains(where: { $0.id == new.id }))
    }

    @Test
    func `createPad links the new pad to the requested team and question`() async throws {
        let new = try await client.createPad(PadCreate(
            title: "Team + question pad",
            language: "python3",
            questionID: 101,
            teamID: "demo-team"
        ))
        #expect(new.team?.id == "demo-team")
        #expect(new.questionIDs == [101])
    }

    @Test
    func `pad decodes the events convenience URL`() async throws {
        let pads = try await client.listPads()
        let pad = try #require(pads.first)
        #expect(pad.events?.contains("/api/pads/\(pad.id)/events") == true)
    }

    @Test
    func `updatePad persists changes and returns fresh state without a PUT body`() async throws {
        // The mock's PUT now returns only {"status":"OK"} (like the live API), so this
        // exercises the re-fetch path rather than decoding a pad from the PUT response.
        let updated = try await client.updatePad(PadUpdate(id: "DEMOPLY3", title: "Renamed pad"))
        #expect(updated.id == "DEMOPLY3")
        #expect(updated.title == "Renamed pad")
    }

    @Test
    func `updatePad can reset contents and attach a question`() async throws {
        let withContents = try await client.updatePad(
            PadUpdate(id: "DEMOABC1", contents: "print('reset')")
        )
        #expect(withContents.contents == "print('reset')")

        let withQuestion = try await client.updatePad(
            PadUpdate(id: "DEMOSWFT5", questionID: 102)
        )
        #expect(withQuestion.questionIDs == [102])
    }

    @Test
    func `createQuestion round-trips title and language sent via nested question params`() async throws {
        let created = try await client.createQuestion(QuestionCreate(
            title: "Nested params question",
            language: "swift"
        ))
        #expect(created.title == "Nested params question")
        #expect(created.language == "swift")
    }

    @Test
    func `updateQuestion persists changes and returns fresh state without a PUT body`() async throws {
        let updated = try await client.updateQuestion(QuestionUpdate(id: 102, title: "Renamed question"))
        #expect(updated.id == 102)
        #expect(updated.title == "Renamed question")
    }

    @Test
    func `getPad on an unknown id returns a 404 mapped error`() async throws {
        await #expect(throws: CoderPadError.self) {
            _ = try await client.getPad(id: "NOPE")
        }
    }

    @Test
    func `the demo account's user email owns mock pads, so its My Pads isn't empty`() async throws {
        let pads = try await client.listPads()
        #expect(pads.contains { $0.ownerEmail == Account.demoUserEmail })
    }
}

/// Backs the "bad key" demo account: the mock server answers 401 for every request,
/// so the unauthorized banner and error states can be exercised without a real
/// revoked key. No shared mutable state, so this suite needn't be serialized.
@Suite("Unauthorized mock server")
struct UnauthorizedMockServerTests {
    private let client = CoderPadClient.mock(unauthorized: true)

    @Test
    func `organization() throws an unauthorized 401 error`() async throws {
        let error = await #expect(throws: CoderPadError.self) {
            _ = try await client.organization()
        }
        #expect(error?.isUnauthorized == true)
        if case let .http(code, _) = error {
            #expect(code == 401)
        } else {
            Issue.record("Expected a .http error, got \(String(describing: error))")
        }
    }

    @Test
    func `listPads() also 401s, so the whole client is gated`() async throws {
        let error = await #expect(throws: CoderPadError.self) {
            _ = try await client.listPads()
        }
        #expect(error?.isUnauthorized == true)
    }
}

/// Fails every request with an offline `URLError`, so the client's transport-error
/// handling can be exercised without real networking.
private final nonisolated class OfflineURLProtocol: URLProtocol {
    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}

@Suite("Transport-error wrapping")
struct NetworkErrorWrappingTests {
    private func offlineClient() -> CoderPadClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineURLProtocol.self]
        return CoderPadClient(apiKey: "test-key", session: URLSession(configuration: config))
    }

    @Test
    func `a transport failure surfaces as a friendly CoderPadError.network, end to end`() async throws {
        let error = await #expect(throws: CoderPadError.self) {
            _ = try await offlineClient().quota()
        }
        guard case .network = error else {
            Issue.record("Expected a .network error, got \(String(describing: error))")
            return
        }

        // The user-facing copy, not the raw URLError.
        #expect(error?.errorDescription?.contains("offline") == true)
        #expect(error?.errorDescription?.contains("Error Domain") != true)
    }

    /// The pad list loads through the incremental stream, not a single `fetch`. A
    /// transport failure there must throw *out* of the `for try await`, so the view
    /// drops its spinner into an error state — otherwise the list "spins forever"
    /// when the sandbox/network blocks the request (issue #75).
    @Test
    func `the incremental pads stream fails closed on a transport error, never hanging`() async throws {
        let error = await #expect(throws: CoderPadError.self) {
            for try await _ in offlineClient().listPadsIncrementally() {
                // Draining the stream; the offline protocol fails page 1, so the
                // loop must rethrow rather than completing silently or hanging.
            }
        }
        guard case .network = error else {
            Issue.record("Expected a .network error, got \(String(describing: error))")
            return
        }

        #expect(error?.errorDescription?.contains("offline") == true)
    }
}
