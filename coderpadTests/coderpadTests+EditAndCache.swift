//
//  coderpadTests+EditAndCache.swift
//  coderpadTests
//
//  Covers the optimistic per-field edit helpers that let the inline editors skip the
//  redundant re-GET (#376) and the shared organization cache that coalesces repeated
//  `/api/organization` fetches (#374).
//

@testable import CoderPad
import Foundation
import Testing

@Suite("New question request normalization")
struct NewQuestionRequestNormalizationTests {
    @Test
    func `create body trims title and optional long form fields`() {
        let body = NewQuestionSheet.normalizedCreateBody(NewQuestionSheet.CreateDraft(
            title: "  Two Sum  \n",
            language: "python3",
            description: "\n  Find a pair.  ",
            instructions: "  Return indices. \n",
            solution: "  use a map  ",
            padType: "take-home"
        ))

        #expect(body.title == "Two Sum")
        #expect(body.description == "Find a pair.")
        #expect(body.solution == "use a map")
        #expect(body.takeHome == true)
        #expect(body.padType == "take-home")
        #expect(body.candidateInstructions?.map(\.instructions) == ["Return indices."])
    }

    @Test
    func `create body omits whitespace only optional sections`() {
        let body = NewQuestionSheet.normalizedCreateBody(NewQuestionSheet.CreateDraft(
            title: "Title",
            language: "python3",
            description: " \n ",
            instructions: "\t",
            solution: "",
            padType: "live"
        ))

        #expect(body.title == "Title")
        #expect(body.description == nil)
        #expect(body.solution == nil)
        #expect(body.takeHome == false)
        #expect(body.padType == "live")
        #expect(body.candidateInstructions == nil)
    }
}

/// Each test gets its own mock client keyed by a unique API key, so its mutations and
/// the client-identity-keyed org cache stay isolated and the suite runs in parallel.
@Suite("Optimistic edits and org cache")
struct EditAndCacheTests {
    private let client = CoderPadClient.mock(key: "test-\(UUID().uuidString)")

    @Test
    func `updatePadWithoutRefetch persists the change without re-fetching (#376)`() async throws {
        // The inline editors PUT then trust their optimistic copy, so this method skips
        // the follow-up GET. Confirm the PUT still landed by fetching separately.
        try await client.updatePadWithoutRefetch(PadUpdate(id: "DEMOPLY3", title: "Optimistic title"))
        let reloaded = try await client.getPad(id: "DEMOPLY3")
        #expect(reloaded.title == "Optimistic title")
    }

    @Test
    func `updateQuestionWithoutRefetch persists the change without re-fetching (#376)`() async throws {
        try await client.updateQuestionWithoutRefetch(QuestionUpdate(id: 102, title: "Optimistic question"))
        let reloaded = try await client.getQuestion(id: 102)
        #expect(reloaded.title == "Optimistic question")
    }

    @Test
    func `pad applying overrides only the named fields, matching the server (#376)`() async throws {
        let pad = try #require(try await client.listPads().first)
        let optimistic = pad.applying(title: "Local title", isPrivate: !(pad.isPrivate ?? false))

        // The changed fields reflect the edit; everything else is carried through, so the
        // optimistic copy is a faithful stand-in for a re-fetch of the same edit.
        #expect(optimistic.title == "Local title")
        #expect(optimistic.isPrivate == !(pad.isPrivate ?? false))
        #expect(optimistic.id == pad.id)
        #expect(optimistic.ownerEmail == pad.ownerEmail)
        #expect(optimistic.language == pad.language)
        #expect(optimistic.executionEnabled == pad.executionEnabled)
        #expect(optimistic.url == pad.url)
        #expect(optimistic.createdAt == pad.createdAt)
    }

    @Test
    func `question applying overrides metadata and content, carrying the rest (#376)`() async throws {
        let question = try #require(try await client.listQuestions().first)
        let optimistic = question.applying(
            title: "Local question", language: "swift",
            solution: "let answer = 42",
            candidateInstructions: [CandidateInstructionPayload(instructions: "Step 1", defaultVisible: true)]
        )

        #expect(optimistic.title == "Local question")
        #expect(optimistic.language == "swift")
        #expect(optimistic.solution == "let answer = 42")
        #expect(optimistic.candidateInstructions.map(\.instructions) == ["Step 1"])
        #expect(optimistic.id == question.id)
        #expect(optimistic.ownerEmail == question.ownerEmail)
        #expect(optimistic.description == question.description)
        #expect(optimistic.createdAt == question.createdAt)
    }

    @Test @MainActor
    func `org cache coalesces and caches the org per client (#374)`() async throws {
        let store = OrganizationCacheStore.shared
        // Two concurrent fetches for the same client coalesce onto one request and both
        // see the same org; a later call is served from the session cache.
        async let first = store.organization(via: client)
        async let second = store.organization(via: client)
        let (orgA, orgB) = try await (first, second)
        #expect(orgA.organizationName == orgB.organizationName)
        #expect(!orgA.users.isEmpty)

        let cached = try await store.organization(via: client)
        #expect(cached.organizationName == orgA.organizationName)
    }

    @Test @MainActor
    func `pad detail cache separates same pad id by backend (#760)`() throws {
        let store = PadDetailCacheStore.shared
        let padID = "shared-slug-\(UUID().uuidString)"
        let first = try CoderPadClient.live(
            apiKey: "key-a-\(UUID().uuidString)",
            baseURL: #require(URL(string: "https://first.example.com"))
        )
        let second = try CoderPadClient.live(
            apiKey: "key-b-\(UUID().uuidString)",
            baseURL: #require(URL(string: "https://second.example.com"))
        )

        store.set(padID, client: first, events: [], environments: [])

        #expect(store.get(padID, client: first) != nil)
        #expect(store.get(padID, client: second) == nil)
    }
}
