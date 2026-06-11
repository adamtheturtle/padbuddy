//
//  coderpadTests.swift
//  coderpadTests
//

import Testing
import Foundation
@testable import coderpad

@Suite("Pad decoder")
struct PadDecoderTests {

    private func decode(_ json: String) throws -> Pad {
        let data = Data(json.utf8)
        return try CoderPadClient.decoder.decode(Pad.self, from: data)
    }

    @Test("decodes a full pad")
    func fullPad() throws {
        let json = """
        {
          "id": "ABC123",
          "title": "Onsite",
          "state": "started",
          "owner_email": "owner@x.co",
          "language": "python3",
          "private": false,
          "execution_enabled": true,
          "participants": ["Jane", "Joe"],
          "url": "https://app.coderpad.io/ABC123",
          "playback": "https://app.coderpad.io/ABC123/playback",
          "created_at": "2026-06-09T23:02:35Z",
          "updated_at": "2026-06-09T23:09:23Z",
          "ended_at": null,
          "type": "live",
          "active_environment_id": 1,
          "pad_environment_ids": [1, 2],
          "question_ids": [42],
          "team": {"id": "team-1", "name": "Cursor"}
        }
        """
        let pad = try decode(json)
        #expect(pad.id == "ABC123")
        #expect(pad.title == "Onsite")
        #expect(pad.state == "started")
        #expect(pad.ownerEmail == "owner@x.co")
        #expect(pad.language == "python3")
        #expect(pad.participants == ["Jane", "Joe"])
        #expect(pad.padEnvironmentIDs == [1, 2])
        #expect(pad.questionIDs == [42])
        #expect(pad.team?.name == "Cursor")
        #expect(pad.executionEnabled == true)
        #expect(pad.isPrivate == false)
        #expect(pad.createdAt != nil)
    }

    @Test("decodes a minimal pad with only an id")
    func minimalPad() throws {
        let pad = try decode(#"{"id": "X1"}"#)
        #expect(pad.id == "X1")
        #expect(pad.title == "")
        #expect(pad.state == "unknown")
        #expect(pad.ownerEmail == "")
        #expect(pad.participants.isEmpty)
        #expect(pad.padEnvironmentIDs.isEmpty)
        #expect(pad.questionIDs.isEmpty)
        #expect(pad.team == nil)
    }

    @Test("tolerates null and missing fields")
    func nullsAndMissing() throws {
        let json = """
        {
          "id": "X2",
          "title": null,
          "state": null,
          "owner_email": null,
          "language": null,
          "participants": null,
          "url": null,
          "playback": null,
          "created_at": null,
          "updated_at": null,
          "ended_at": null,
          "type": null,
          "execution_enabled": null,
          "private": null,
          "active_environment_id": null,
          "pad_environment_ids": null,
          "question_ids": null,
          "team": null
        }
        """
        let pad = try decode(json)
        #expect(pad.id == "X2")
        #expect(pad.title == "")
        #expect(pad.state == "unknown")
        #expect(pad.participants.isEmpty)
        #expect(pad.padEnvironmentIDs.isEmpty)
        #expect(pad.questionIDs.isEmpty)
    }

    @Test("decodes both ISO8601 with Z and with offset+fractional seconds")
    func dateFormats() throws {
        let json = """
        {
          "id": "X3",
          "created_at": "2026-06-09T23:02:35Z",
          "updated_at": "2025-04-24T17:00:00.000-07:00"
        }
        """
        let pad = try decode(json)
        #expect(pad.createdAt != nil)
        #expect(pad.updatedAt != nil)
    }

    @Test("fails clearly when id is missing")
    func missingID() {
        #expect(throws: DecodingError.self) {
            try decode(#"{"title": "no id"}"#)
        }
    }
}

@Suite("Question decoder")
struct QuestionDecoderTests {

    private func decode(_ json: String) throws -> Question {
        try CoderPadClient.decoder.decode(Question.self, from: Data(json.utf8))
    }

    @Test("decodes a full question")
    func fullQuestion() throws {
        let json = """
        {
          "id": 42,
          "title": "Date Picker",
          "owner_email": "a@x.co",
          "language": "python3",
          "description": "desc",
          "candidate_instructions": [{"instructions": "go!", "default_visible": true}],
          "shared": true,
          "used": 12,
          "take_home": false,
          "test_cases_enabled": true,
          "solution": "sol",
          "pad_type": "live",
          "is_draft": false,
          "author_name": "Adam",
          "organization_name": "Cursor",
          "created_at": "2025-08-25T16:03:44Z",
          "updated_at": "2026-05-22T06:38:19Z"
        }
        """
        let q = try decode(json)
        #expect(q.id == 42)
        #expect(q.title == "Date Picker")
        #expect(q.ownerEmail == "a@x.co")
        #expect(q.language == "python3")
        #expect(q.used == 12)
        #expect(q.candidateInstructions.count == 1)
        #expect(q.candidateInstructions.first?.instructions == "go!")
        #expect(q.authorName == "Adam")
    }

    @Test("decodes a minimal question with id only")
    func minimalQuestion() throws {
        let q = try decode(#"{"id": 1}"#)
        #expect(q.id == 1)
        #expect(q.title == "")
        #expect(q.ownerEmail == "")
        #expect(q.candidateInstructions.isEmpty)
    }

    @Test("tolerates null fields throughout")
    func nullsThroughout() throws {
        let json = """
        {
          "id": 2,
          "title": null,
          "owner_email": null,
          "language": null,
          "description": null,
          "candidate_instructions": null,
          "shared": null,
          "used": null,
          "take_home": null,
          "test_cases_enabled": null,
          "solution": null,
          "pad_type": null,
          "is_draft": null,
          "author_name": null,
          "organization_name": null,
          "created_at": null,
          "updated_at": null
        }
        """
        let q = try decode(json)
        #expect(q.id == 2)
        #expect(q.candidateInstructions.isEmpty)
    }
}

// Serialized: these tests share MockFixtures' process-wide mutable state (created /
// updated / deleted pads), so concurrent execution would race on pad counts.
@Suite("Mock server end-to-end", .serialized)
struct MockServerTests {

    private let client = CoderPadClient.mock()

    @Test("listPads returns the seeded pads")
    func listPads() async throws {
        let pads = try await client.listPads()
        #expect(pads.count >= 5)
        #expect(pads.contains(where: { $0.id == "DEMOABC1" }))
        #expect(pads.allSatisfy { !$0.id.isEmpty })
    }

    @Test("listPadsIncrementally yields page 1 first, then the full list")
    func listPadsIncrementally() async throws {
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

    @Test("getPad returns a specific pad")
    func getPad() async throws {
        let pad = try await client.getPad(id: "DEMOABC1")
        #expect(pad.title == "Onsite: Jane Doe")
        #expect(pad.ownerEmail == "alex@demo.co")
        #expect(pad.participants == ["Jane Doe", "Alex Park"])
    }

    @Test("padEvents returns events for a pad")
    func padEvents() async throws {
        let events = try await client.padEvents(padID: "DEMOABC1")
        #expect(events.count == 4)
        #expect(events.first?.kind == "started")
        #expect(events.contains(where: { $0.kind == "ran" }))
    }

    @Test("padEnvironment returns the requested environment")
    func padEnvironment() async throws {
        let env = try await client.padEnvironment(id: 1)
        #expect(env.id == 1)
        #expect(env.language == "python3")
        #expect(env.fileContents.first?.path == "coderpad/main.py")
        #expect(env.contents?.contains("Hello") == true)
    }

    @Test("listQuestions returns the seeded questions")
    func listQuestions() async throws {
        let qs = try await client.listQuestions()
        #expect(qs.count == 3)
        #expect(qs.contains(where: { $0.title == "FizzBuzz" }))
    }

    @Test("organization returns the demo org with users")
    func organization() async throws {
        let org = try await client.organization()
        #expect(org.organizationName == "Demo Org")
        #expect(org.users.count >= 5)
        #expect(org.users.contains(where: { $0.email == "alex@demo.co" }))
    }

    @Test("quota returns the demo plan")
    func quota() async throws {
        let q = try await client.quota()
        #expect(q.padsUsed == 24)
        #expect(q.unlimited == false)
        #expect(q.overagesEnabled == true)
        #expect(q.quotaReset != nil)
        #expect(q.padsRemaining == 96)
        #expect(q.billingCyclePadLimit == 120)
    }

    @Test("organizationUsers filters by email when provided")
    func organizationUsersByEmail() async throws {
        let all = try await client.organizationUsers()
        #expect(all.count >= 5)
        let one = try await client.organizationUsers(email: "alex@demo.co")
        #expect(one.count == 1)
        #expect(one.first?.email == "alex@demo.co")
    }

    @Test("listOrganizationPads and questions return org-wide data")
    func organizationWideLists() async throws {
        let pads = try await client.listOrganizationPads()
        #expect(!pads.isEmpty)
        let questions = try await client.listOrganizationQuestions()
        #expect(!questions.isEmpty)
    }

    @Test("endPad marks the pad ended")
    func endPad() async throws {
        // DEMOABC1 is a seeded pad, so the mock's update merge applies; ending only
        // flips state/ended_at, leaving the pad listable for other tests.
        try await client.endPad(id: "DEMOABC1")
        let pad = try await client.getPad(id: "DEMOABC1")
        #expect(pad.state == "ended")
        #expect(pad.endedAt != nil)
    }

    @Test("deletePad removes a created pad from listings")
    func deletePad() async throws {
        // Delete a freshly created pad rather than a seed, so the suite's
        // "listPads returns the seeded pads" invariant is unaffected.
        let new = try await client.createPad(PadCreate(title: "To delete"))
        try await client.deletePad(id: new.id)
        let after = try await client.listPads()
        #expect(!after.contains(where: { $0.id == new.id }))
    }

    @Test("createPad echoes a new pad and makes it listable")
    func createPad() async throws {
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

    @Test("createPad links the new pad to the requested team and question")
    func createPadTeamAndQuestion() async throws {
        let new = try await client.createPad(PadCreate(
            title: "Team + question pad",
            language: "python3",
            questionID: 101,
            teamID: "demo-team"
        ))
        #expect(new.team?.id == "demo-team")
        #expect(new.questionIDs == [101])
    }

    @Test("Pad decodes the events convenience URL")
    func padEventsURLDecoded() async throws {
        let pads = try await client.listPads()
        let pad = try #require(pads.first)
        #expect(pad.events?.contains("/api/pads/\(pad.id)/events") == true)
    }

    @Test("updatePad persists changes and returns fresh state without a PUT body")
    func updatePad() async throws {
        // The mock's PUT now returns only {"status":"OK"} (like the live API), so this
        // exercises the re-fetch path rather than decoding a pad from the PUT response.
        let updated = try await client.updatePad(PadUpdate(id: "DEMOPLY3", title: "Renamed pad"))
        #expect(updated.id == "DEMOPLY3")
        #expect(updated.title == "Renamed pad")
    }

    @Test("updatePad can reset contents and attach a question")
    func updatePadContentsAndQuestion() async throws {
        let withContents = try await client.updatePad(
            PadUpdate(id: "DEMOABC1", contents: "print('reset')"))
        #expect(withContents.contents == "print('reset')")

        let withQuestion = try await client.updatePad(
            PadUpdate(id: "DEMOSWFT5", questionID: 102))
        #expect(withQuestion.questionIDs == [102])
    }

    @Test("createQuestion round-trips title and language sent via nested question params")
    func createQuestionNestedParams() async throws {
        let created = try await client.createQuestion(QuestionCreate(
            title: "Nested params question",
            language: "swift"))
        #expect(created.title == "Nested params question")
        #expect(created.language == "swift")
    }

    @Test("updateQuestion persists changes and returns fresh state without a PUT body")
    func updateQuestion() async throws {
        let updated = try await client.updateQuestion(QuestionUpdate(id: 102, title: "Renamed question"))
        #expect(updated.id == 102)
        #expect(updated.title == "Renamed question")
    }

    @Test("getPad on an unknown id returns a 404 mapped error")
    func unknownPad() async throws {
        await #expect(throws: CoderPadError.self) {
            _ = try await client.getPad(id: "NOPE")
        }
    }
}

@Suite("Language helpers")
struct LanguageHelperTests {
    @Test("languageDisplayName maps known codes to friendly names")
    func displayNames() {
        #expect("python3".languageDisplayName == "Python 3")
        #expect("python2".languageDisplayName == "Python 2")
        #expect("javascript".languageDisplayName == "JavaScript")
        #expect("typescript".languageDisplayName == "TypeScript")
        #expect("nodejs".languageDisplayName == "Node.js")
        #expect("cpp".languageDisplayName == "C++")
        #expect("csharp".languageDisplayName == "C#")
        #expect("objective-c".languageDisplayName == "Objective-C")
        #expect("postgresql".languageDisplayName == "PostgreSQL")
        #expect("fsharp".languageDisplayName == "F#")
    }

    @Test("languageDisplayName names multifile project environments")
    func multifileNames() {
        #expect("multifile_java".languageDisplayName == "Java Project")
        #expect("Multifile_java".languageDisplayName == "Java Project")
        #expect("multifile_python3".languageDisplayName == "Python 3 Project")
        #expect("multifile_nodejs".languageDisplayName == "Node.js Project")
    }

    @Test("languageDisplayName capitalizes unknown codes")
    func unknownNames() {
        #expect("zig".languageDisplayName == "Zig")
        #expect("".languageDisplayName == "")
    }

    @Test("languageSymbol falls back for unknown languages")
    func symbolFallback() {
        #expect("python3".languageSymbol == "terminal")
        #expect("javascript".languageSymbol == "globe")
        #expect("swift".languageSymbol == "swift")
        #expect("rust".languageSymbol == "cpu")
        #expect("sql".languageSymbol == "cylinder")
        #expect("zig".languageSymbol == "chevron.left.slash.chevron.right")
    }
}

@Suite("Account round-trip")
struct AccountRoundTripTests {
    @Test("Account encodes/decodes through JSON without loss")
    func roundTrip() throws {
        let original = Account(name: "Production", apiKey: "secret-key", isMock: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.apiKey == original.apiKey)
        #expect(decoded.isMock == original.isMock)
    }

    @Test("Demo account survives the round-trip with isMock = true")
    func demoRoundTrip() throws {
        let demo = Account.demo()
        let data = try JSONEncoder().encode(demo)
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        #expect(decoded.isMock == true)
        #expect(decoded.name == "Demo (mock data)")
    }
}

@Suite("What's New gating", .serialized)
struct WhatsNewTests {
    private static let key = "lastSeenWhatsNewVersion"

    private func withCleanDefault<T>(_ block: () throws -> T) rethrows -> T {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        UserDefaults.standard.removeObject(forKey: Self.key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: Self.key)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.key)
            }
        }
        return try block()
    }

    @Test("shouldShow returns true on clean install")
    func cleanInstall() {
        withCleanDefault {
            #expect(WhatsNew.shouldShow() == true)
        }
    }

    @Test("markSeen suppresses future prompts for the same version")
    func markSeen() {
        withCleanDefault {
            WhatsNew.markSeen()
            #expect(WhatsNew.shouldShow() == false)
        }
    }

    @Test("an older recorded version still triggers the prompt")
    func olderVersion() {
        withCleanDefault {
            UserDefaults.standard.set("0.1", forKey: Self.key)
            #expect(WhatsNew.shouldShow() == true)
        }
    }
}

@Suite("Quota decoder")
struct QuotaDecoderTests {
    @Test("parses dates with timezone offset and fractional seconds")
    func parses() throws {
        let json = """
        {
          "status": "OK",
          "trial_expires_at": "2025-04-24T17:00:00.000-07:00",
          "pads_used": 57,
          "quota_reset_at": "2026-05-29T00:05:00.000-07:00",
          "unlimited": true,
          "overages_enabled": false
        }
        """
        let q = try CoderPadClient.decoder.decode(Quota.self, from: Data(json.utf8))
        #expect(q.padsUsed == 57)
        #expect(q.unlimited == true)
        #expect(q.overagesEnabled == false)
        #expect(q.trialExpiresAt != nil)
        #expect(q.quotaReset != nil)
    }
}
