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

@Suite("Mock server end-to-end")
struct MockServerTests {

    private let client = CoderPadClient.mock()

    @Test("listPads returns the seeded pads")
    func listPads() async throws {
        let pads = try await client.listPads()
        #expect(pads.count >= 5)
        #expect(pads.contains(where: { $0.id == "DEMOABC1" }))
        #expect(pads.allSatisfy { !$0.id.isEmpty })
    }

    @Test("getPad returns a specific pad")
    func getPad() async throws {
        let pad = try await client.getPad(id: "DEMOABC1")
        #expect(pad.title == "Onsite — Jane Doe")
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
        #expect(env.title == "Main")
        #expect(env.language == "python3")
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

    @Test("getPad on an unknown id returns a 404 mapped error")
    func unknownPad() async throws {
        await #expect(throws: CoderPadError.self) {
            _ = try await client.getPad(id: "NOPE")
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
