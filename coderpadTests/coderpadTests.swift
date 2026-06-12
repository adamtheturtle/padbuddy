//
//  coderpadTests.swift
//  coderpadTests
//

import Testing
import Foundation
import SwiftUI
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

    @Test("drops null entries inside the participants array")
    func nullParticipantEntries() throws {
        let json = """
        {
          "id": "X4",
          "participants": ["Jane", null, "Joe"]
        }
        """
        let pad = try decode(json)
        #expect(pad.participants == ["Jane", "Joe"])
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

    @Test("decodes test cases, mapping return_value and visibility")
    func questionTestCases() throws {
        let json = """
        {
          "id": 7,
          "test_cases_enabled": true,
          "test_cases": [
            {"id": 1, "arguments": ["3"], "return_value": "Fizz", "visible": true},
            {"id": 2, "arguments": ["15"], "return_value": "FizzBuzz", "visible": false}
          ]
        }
        """
        let q = try decode(json)
        #expect(q.testCases.count == 2)
        #expect(q.testCases.first?.arguments == ["3"])
        #expect(q.testCases.first?.returnValue == "Fizz")
        #expect(q.testCases.first?.visible == true)
        #expect(q.testCases.last?.visible == false)
    }

    @Test("defaults test cases to empty when the field is absent")
    func questionTestCasesAbsent() throws {
        let q = try decode(#"{"id": 8}"#)
        #expect(q.testCases.isEmpty)
    }

    @Test("decodes custom file metadata")
    func questionCustomFiles() throws {
        let json = """
        {
          "id": 9,
          "custom_files": [
            {"id": "cf1", "title": "Starter", "description": "Boilerplate",
             "filename": "main.py", "filesize": "1.2 KB"}
          ]
        }
        """
        let q = try decode(json)
        #expect(q.customFiles.count == 1)
        #expect(q.customFiles.first?.filename == "main.py")
        #expect(q.customFiles.first?.filesize == "1.2 KB")
        #expect(q.customFiles.first?.title == "Starter")
    }

    @Test("defaults custom files to empty when the field is absent")
    func questionCustomFilesAbsent() throws {
        let q = try decode(#"{"id": 10}"#)
        #expect(q.customFiles.isEmpty)
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

    @Test("a pad exposes its whiteboard drawing URL")
    func padDrawing() async throws {
        let pad = try await client.getPad(id: "DEMOXYZ2")
        let drawing = try #require(pad.drawing)
        #expect(!drawing.isEmpty)
        #expect(URL(string: drawing) != nil)
        // Pads without a whiteboard decode it as nil rather than an empty string.
        let noDrawing = try await client.getPad(id: "DEMOABC1")
        #expect(noDrawing.drawing == nil)
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
        // Backs the org-default language pre-selection in the create sheets.
        #expect(org.organizationDefaultLanguage == "go")
        // Backs the Organization view's single sign-on row and portal action.
        #expect(org.singleSignOnSupported == true)
        #expect(org.singleSignInURL == "https://app.coderpad.io/sso/demo-org")
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

    @Test("the demo account's user email owns mock pads, so its My Pads isn't empty")
    func demoEmailOwnsMockPads() async throws {
        let pads = try await client.listPads()
        #expect(pads.contains { $0.ownerEmail == Account.demoUserEmail })
    }
}

// Backs the "bad key" demo account: the mock server answers 401 for every request,
// so the unauthorized banner and error states can be exercised without a real
// revoked key. No shared mutable state, so this suite needn't be serialized.
@Suite("Unauthorized mock server")
struct UnauthorizedMockServerTests {

    private let client = CoderPadClient.mock(unauthorized: true)

    @Test("organization() throws an unauthorized 401 error")
    func organizationUnauthorized() async throws {
        let error = await #expect(throws: CoderPadError.self) {
            _ = try await client.organization()
        }
        #expect(error?.isUnauthorized == true)
        if case .http(let code, _) = error {
            #expect(code == 401)
        } else {
            Issue.record("Expected a .http error, got \(String(describing: error))")
        }
    }

    @Test("listPads() also 401s, so the whole client is gated")
    func listPadsUnauthorized() async throws {
        let error = await #expect(throws: CoderPadError.self) {
            _ = try await client.listPads()
        }
        #expect(error?.isUnauthorized == true)
    }
}

@Suite("Language helpers")
struct LanguageHelperTests {
    @Test("languageDisplayName maps known codes to friendly names", arguments: [
        ("python3", "Python 3"),
        ("python2", "Python 2"),
        ("javascript", "JavaScript"),
        ("typescript", "TypeScript"),
        ("nodejs", "Node.js"),
        ("cpp", "C++"),
        ("csharp", "C#"),
        ("objective-c", "Objective-C"),
        ("postgresql", "PostgreSQL"),
        ("fsharp", "F#"),
    ])
    func displayNames(code: String, expected: String) {
        #expect(code.languageDisplayName == expected)
    }

    @Test("languageDisplayName names multifile project environments", arguments: [
        ("multifile_java", "Java Project"),
        ("Multifile_java", "Java Project"),
        ("multifile_python3", "Python 3 Project"),
        ("multifile_nodejs", "Node.js Project"),
    ])
    func multifileNames(code: String, expected: String) {
        #expect(code.languageDisplayName == expected)
    }

    @Test("languageDisplayName capitalizes unknown codes", arguments: [
        ("zig", "Zig"),
        ("", ""),
    ])
    func unknownNames(code: String, expected: String) {
        #expect(code.languageDisplayName == expected)
    }

    @Test("languageSymbol falls back for unknown languages", arguments: [
        ("python3", "terminal"),
        ("javascript", "globe"),
        ("swift", "swift"),
        ("rust", "cpu"),
        ("sql", "cylinder"),
        ("zig", "chevron.left.slash.chevron.right"),
    ])
    func symbolFallback(code: String, expected: String) {
        #expect(code.languageSymbol == expected)
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

    @Test("Demo accounts carry the required user email")
    func demoAccountsHaveEmail() {
        #expect(Account.demo().userEmail == Account.demoUserEmail)
        #expect(Account.demoBadKey().userEmail == Account.demoUserEmail)
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

    @Test("the gate is keyed on the live app version, not a hardcoded constant")
    func gatesOnAppVersion() {
        withCleanDefault {
            // markSeen must record exactly the version the gate compares against, so
            // a MARKETING_VERSION bump (which changes WhatsNew.version) re-shows the
            // sheet without anyone editing a second constant.
            #expect(!WhatsNew.version.isEmpty)
            #expect(WhatsNew.current.version == WhatsNew.version)
            WhatsNew.markSeen()
            #expect(UserDefaults.standard.string(forKey: Self.key) == WhatsNew.version)

            // Recording any other version re-arms the prompt.
            UserDefaults.standard.set(WhatsNew.version + "-old", forKey: Self.key)
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

@Suite("App appearance")
struct AppAppearanceTests {
    @Test("raw values are stable (they back the stored preference)", arguments: [
        (AppAppearance.system, "system"),
        (AppAppearance.light, "light"),
        (AppAppearance.dark, "dark"),
    ])
    func rawValues(appearance: AppAppearance, rawValue: String) {
        #expect(appearance.rawValue == rawValue)
    }

    @Test("maps to the color scheme it forces, nil for system", arguments: [
        (AppAppearance.system, ColorScheme?.none),
        (AppAppearance.light, .light),
        (AppAppearance.dark, .dark),
    ])
    func colorScheme(appearance: AppAppearance, scheme: ColorScheme?) {
        #expect(appearance.colorScheme == scheme)
    }

    @Test("every case has a non-empty label")
    func labels() {
        #expect(AppAppearance.allCases.allSatisfy { !$0.label.isEmpty })
    }
}

// Serialized: these read and mutate process-wide UserDefaults under the
// `general.*` keys, so concurrent runs would clobber each other's values.
@Suite("General settings", .serialized)
struct GeneralSettingsTests {
    private static let keys = [
        GeneralSettings.Key.appearance,
        GeneralSettings.Key.hideDockIcon,
        GeneralSettings.Key.refreshSeconds,
    ]

    /// Snapshots the `general.*` defaults, clears them, runs the block, then restores
    /// whatever was there before so the test leaves no trace.
    private func withCleanDefaults<T>(_ block: () throws -> T) rethrows -> T {
        let saved = Self.keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        for key in Self.keys { UserDefaults.standard.removeObject(forKey: key) }
        defer {
            for (key, value) in saved {
                if let value {
                    UserDefaults.standard.set(value, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        return try block()
    }

    @Test("refreshSeconds falls back to the default when unset")
    func refreshDefault() {
        withCleanDefaults {
            #expect(GeneralSettings.refreshSeconds == GeneralSettings.defaultRefreshSeconds)
            #expect(GeneralSettings.refreshInterval == .seconds(GeneralSettings.defaultRefreshSeconds))
        }
    }

    @Test("refreshSeconds passes a valid stored value through")
    func refreshPassthrough() {
        withCleanDefaults {
            UserDefaults.standard.set(120, forKey: GeneralSettings.Key.refreshSeconds)
            #expect(GeneralSettings.refreshSeconds == 120)
            #expect(GeneralSettings.refreshInterval == .seconds(120))
        }
    }

    @Test("refreshSeconds clamps below the minimum and above the maximum")
    func refreshClamping() {
        withCleanDefaults {
            UserDefaults.standard.set(1, forKey: GeneralSettings.Key.refreshSeconds)
            #expect(GeneralSettings.refreshSeconds == GeneralSettings.minRefreshSeconds)

            UserDefaults.standard.set(99_999, forKey: GeneralSettings.Key.refreshSeconds)
            #expect(GeneralSettings.refreshSeconds == GeneralSettings.maxRefreshSeconds)
        }
    }

    @Test("appearance defaults to system and reads back a stored choice")
    func appearance() {
        withCleanDefaults {
            #expect(GeneralSettings.appearance == .system)

            UserDefaults.standard.set("dark", forKey: GeneralSettings.Key.appearance)
            #expect(GeneralSettings.appearance == .dark)

            // An unrecognized stored value falls back to system rather than crashing.
            UserDefaults.standard.set("chartreuse", forKey: GeneralSettings.Key.appearance)
            #expect(GeneralSettings.appearance == .system)
        }
    }

    @Test("hideDockIcon defaults to false and reflects a stored true")
    func hideDockIcon() {
        withCleanDefaults {
            #expect(GeneralSettings.hideDockIcon == false)
            UserDefaults.standard.set(true, forKey: GeneralSettings.Key.hideDockIcon)
            #expect(GeneralSettings.hideDockIcon == true)
        }
    }
}

@Suite("CoderPadError messages")
struct CoderPadErrorMessageTests {

    @Test("HTTP errors never leak the raw response body into the message")
    func hidesRawBody() {
        let error = CoderPadError.http(404, #"{"status":404,"error":"Not Found"}"#)
        let message = try! #require(error.errorDescription)
        // The old message dumped the JSON verbatim; the new one must not.
        #expect(!message.contains("{"))
        #expect(!message.contains("status"))
        #expect(message.contains("deleted"))
    }

    @Test("known status codes get a plain-language explanation")
    func knownCodes() {
        #expect(CoderPadError.http(401, "").errorDescription?.contains("API key") == true)
        #expect(CoderPadError.http(429, "").errorDescription?.contains("rate-limiting") == true)
        #expect(CoderPadError.http(503, "").errorDescription?.contains("server error") == true)
    }

    @Test("an API-supplied message is preferred over a bare HTTP code")
    func surfacesAPIMessage() {
        let error = CoderPadError.http(422, #"{"message":"Title can't be blank"}"#)
        #expect(error.errorDescription == "Title can't be blank")
    }

    @Test("transport failures map to plain-language, actionable messages")
    func networkErrors() {
        #expect(CoderPadError.network(URLError(.notConnectedToInternet)).errorDescription?.contains("offline") == true)
        #expect(CoderPadError.network(URLError(.networkConnectionLost)).errorDescription?.contains("offline") == true)
        #expect(CoderPadError.network(URLError(.timedOut)).errorDescription?.contains("timed out") == true)
        #expect(CoderPadError.network(URLError(.cannotConnectToHost)).errorDescription?.contains("reach CoderPad") == true)
        #expect(CoderPadError.network(URLError(.cannotFindHost)).errorDescription?.contains("reach CoderPad") == true)
        // An unmapped code still gets a useful, non-empty fallback (not a raw URLError dump).
        let fallback = CoderPadError.network(URLError(.badServerResponse)).errorDescription ?? ""
        #expect(fallback.contains("network error"))
        #expect(!fallback.contains("Error Domain"))
    }
}

// MARK: - Pad list logic (filters, date ranges, event grouping)

/// A fixed clock so the date-range tests don't depend on the wall clock, and a
/// UTC calendar so `startOfDay` lands on a known instant regardless of the
/// machine's time zone.
private let fixedNow = ISO8601DateFormatter().date(from: "2026-06-12T12:00:00Z")!
private var utcCalendar: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}

/// Builds a `Pad` through the real lenient decoder so the tests exercise the
/// same construction path the app uses, rather than a hand-rolled initializer.
private func makePad(
    id: String = "P1",
    title: String = "",
    state: String = "started",
    ownerEmail: String = "",
    language: String? = nil,
    type: String? = nil,
    teamName: String? = nil,
    participants: [String] = [],
    updatedAt: String? = nil,
    isPrivate: Bool? = nil
) throws -> Pad {
    var dict: [String: Any] = [
        "id": id,
        "title": title,
        "state": state,
        "owner_email": ownerEmail,
        "participants": participants,
    ]
    if let language { dict["language"] = language }
    if let type { dict["type"] = type }
    if let teamName { dict["team"] = ["id": teamName, "name": teamName] }
    if let updatedAt { dict["updated_at"] = updatedAt }
    if let isPrivate { dict["private"] = isPrivate }
    let data = try JSONSerialization.data(withJSONObject: dict)
    return try CoderPadClient.decoder.decode(Pad.self, from: data)
}

@Suite("Pad date range")
struct PadDateRangeTests {
    @Test("today starts at midnight of the current day")
    func today() {
        let start = PadDateRange.start(for: "today", now: fixedNow, calendar: utcCalendar)
        #expect(start == ISO8601DateFormatter().date(from: "2026-06-12T00:00:00Z"))
    }

    @Test("last 7 days starts seven days before now")
    func sevenDays() {
        let start = PadDateRange.start(for: "last 7 days", now: fixedNow, calendar: utcCalendar)
        #expect(start == ISO8601DateFormatter().date(from: "2026-06-05T12:00:00Z"))
    }

    @Test("last 30 days starts thirty days before now")
    func thirtyDays() {
        let start = PadDateRange.start(for: "last 30 days", now: fixedNow, calendar: utcCalendar)
        #expect(start == ISO8601DateFormatter().date(from: "2026-05-13T12:00:00Z"))
    }

    @Test("an unrecognized option imposes no lower bound")
    func unknown() {
        #expect(PadDateRange.start(for: "all time", now: fixedNow) == nil)
        #expect(PadDateRange.start(for: "", now: fixedNow) == nil)
    }

    @Test("the chip options match the recognized keys")
    func optionsAreRecognized() {
        for option in PadDateRange.options {
            #expect(PadDateRange.start(for: option, now: fixedNow) != nil)
        }
    }
}

@Suite("Pad activity since open")
struct PadActivitySinceOpenTests {
    private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    @Test("started pad updated after last open shows the dot")
    func startedUpdatedAfter() throws {
        let pad = try makePad(state: "started", updatedAt: "2026-06-12T12:00:00Z")
        #expect(PadListLogic.hasNewActivitySinceOpen(pad, lastOpened: date("2026-06-12T11:00:00Z")))
    }

    @Test("started pad updated before last open shows no dot")
    func startedUpdatedBefore() throws {
        let pad = try makePad(state: "started", updatedAt: "2026-06-12T10:00:00Z")
        #expect(!PadListLogic.hasNewActivitySinceOpen(pad, lastOpened: date("2026-06-12T11:00:00Z")))
    }

    @Test("a never-opened pad shows no dot")
    func neverOpened() throws {
        let pad = try makePad(state: "started", updatedAt: "2026-06-12T12:00:00Z")
        #expect(!PadListLogic.hasNewActivitySinceOpen(pad, lastOpened: nil))
    }

    @Test("a non-started pad shows no dot even with new activity")
    func endedPad() throws {
        let pad = try makePad(state: "ended", updatedAt: "2026-06-12T12:00:00Z")
        #expect(!PadListLogic.hasNewActivitySinceOpen(pad, lastOpened: date("2026-06-12T11:00:00Z")))
    }

    @Test("a started pad with no updated_at shows no dot")
    func noUpdatedAt() throws {
        let pad = try makePad(state: "started")
        #expect(!PadListLogic.hasNewActivitySinceOpen(pad, lastOpened: date("2026-06-12T11:00:00Z")))
    }
}

@Suite("Pad bulk action targets")
struct PadBulkActionTests {
    @Test("startedPads keeps only active pads")
    func startedOnly() throws {
        let pads = [
            try makePad(id: "a", state: "started"),
            try makePad(id: "b", state: "ended"),
            try makePad(id: "c", state: "started"),
            try makePad(id: "d", state: "pending"),
        ]
        #expect(PadListLogic.startedPads(in: pads).map(\.id) == ["a", "c"])
    }

    @Test("nonPrivatePads excludes pads already private")
    func nonPrivate() throws {
        let pads = [
            try makePad(id: "a", isPrivate: true),
            try makePad(id: "b", isPrivate: false),
            try makePad(id: "c", isPrivate: nil),
        ]
        #expect(PadListLogic.nonPrivatePads(in: pads).map(\.id) == ["b", "c"])
    }
}

@Suite("Pad refresh cadence")
struct PadRefreshIntervalTests {
    let base = Duration.seconds(90)

    @Test("small list with a started pad uses the base cadence")
    func smallStarted() {
        #expect(PadListLogic.refreshInterval(base: base, padCount: 10, hasStartedPads: true) == base)
    }

    @Test("no started pads backs off 2x")
    func noStarted() {
        #expect(PadListLogic.refreshInterval(base: base, padCount: 10, hasStartedPads: false) == base * 2)
    }

    @Test("large list compounds the size and no-started back-offs")
    func largeNoStarted() {
        #expect(PadListLogic.refreshInterval(base: base, padCount: 5000, hasStartedPads: false) == base * 8)
    }

    @Test("medium list with started pads scales by size only")
    func mediumStarted() {
        #expect(PadListLogic.refreshInterval(base: base, padCount: 1000, hasStartedPads: true) == base * 2)
    }
}

@Suite("Spotlight item identifiers")
struct SpotlightIndexerTests {
    @Test("a pad identifier round-trips the pad id")
    func padIdentifier() {
        #expect(SpotlightIndexer.padID(fromItemIdentifier: "pad:ABC123") == "ABC123")
        #expect(SpotlightIndexer.padID(fromItemIdentifier: "question:42") == nil)
    }

    @Test("a question identifier is recognized")
    func questionIdentifier() {
        #expect(SpotlightIndexer.isQuestion(itemIdentifier: "question:42"))
        #expect(!SpotlightIndexer.isQuestion(itemIdentifier: "pad:ABC123"))
    }
}

@Suite("Pad filtering")
struct PadFilterTests {

    private func samplePads() throws -> [Pad] {
        [
            try makePad(id: "ABC1", title: "Onsite", state: "started",
                        ownerEmail: "alex@demo.co", language: "python3", type: "live",
                        teamName: "Cursor", participants: ["Jane Doe"],
                        updatedAt: "2026-06-11T09:00:00Z"),
            try makePad(id: "XYZ2", title: "Take Home Challenge", state: "ended",
                        ownerEmail: "sam@demo.co", language: "go", type: "take-home",
                        teamName: nil, participants: [],
                        updatedAt: "2026-01-01T09:00:00Z"),
        ]
    }

    @Test("empty criteria returns every pad")
    func noFilters() throws {
        let pads = try samplePads()
        let result = PadListLogic.filter(pads, using: PadFilterCriteria())
        #expect(result.map(\.id) == ["ABC1", "XYZ2"])
    }

    @Test("state filter keeps only matching pads")
    func byState() throws {
        let result = PadListLogic.filter(try samplePads(),
                                         using: PadFilterCriteria(state: .active))
        #expect(result.map(\.id) == ["ABC1"])
    }

    @Test("language filter is case-insensitive")
    func byLanguage() throws {
        let pads = try samplePads()
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(language: "python3")).map(\.id) == ["ABC1"])
        // An upper-cased criterion still matches the lower-cased pad language.
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(language: "PYTHON3")).map(\.id) == ["ABC1"])
    }

    @Test("owner and team filters match exactly")
    func byOwnerAndTeam() throws {
        let pads = try samplePads()
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(owner: "sam@demo.co")).map(\.id) == ["XYZ2"])
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(team: "Cursor")).map(\.id) == ["ABC1"])
    }

    @Test("interview-type filter keeps only the matching type")
    func byType() throws {
        let pads = try samplePads()
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(type: "take-home")).map(\.id) == ["XYZ2"])
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(type: "live")).map(\.id) == ["ABC1"])
    }

    @Test("search matches title, id, owner email, and participants")
    func searchFields() throws {
        let pads = try samplePads()
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(search: "onsite")).map(\.id) == ["ABC1"])
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(search: "abc1")).map(\.id) == ["ABC1"])
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(search: "sam@")).map(\.id) == ["XYZ2"])
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(search: "jane")).map(\.id) == ["ABC1"])
        #expect(PadListLogic.filter(pads, using: PadFilterCriteria(search: "nothinghere")).isEmpty)
    }

    @Test("search also matches the directory-resolved owner display name")
    func searchByDisplayName() throws {
        let pads = try samplePads()
        let display: (String) -> String = { $0 == "alex@demo.co" ? "Alex Park" : $0 }
        // "Alex Park" appears nowhere in the raw pad, only via the directory.
        let result = PadListLogic.filter(pads, using: PadFilterCriteria(search: "alex park"), display: display)
        #expect(result.map(\.id) == ["ABC1"])
    }

    @Test("filters combine with AND")
    func combinedFilters() throws {
        let pads = try samplePads()
        // Active pads that are written in Go: none, since the only Go pad is ended.
        let result = PadListLogic.filter(pads, using: PadFilterCriteria(state: .active, language: "go"))
        #expect(result.isEmpty)
    }

    @Test("date-range filter keeps pads updated within the window")
    func byDateRange() throws {
        let pads = try samplePads()
        // ABC1 was updated yesterday, XYZ2 back in January.
        let recent = PadListLogic.filter(pads, using: PadFilterCriteria(dateRange: "last 7 days"), now: fixedNow)
        #expect(recent.map(\.id) == ["ABC1"])
        let month = PadListLogic.filter(pads, using: PadFilterCriteria(dateRange: "last 30 days"), now: fixedNow)
        #expect(month.map(\.id) == ["ABC1"])
    }
}

@Suite("Pad event grouping")
struct PadEventGroupingTests {

    private func event(_ kind: String, user: String?, at seconds: TimeInterval) -> PadEvent {
        PadEvent(message: "m", kind: kind, metadata: nil, userName: user,
                 userEmail: nil, createdAt: Date(timeIntervalSince1970: seconds))
    }

    @Test("an empty log produces no groups")
    func empty() {
        #expect(PadEventGrouping.group([]).isEmpty)
    }

    @Test("consecutive same-kind, same-user events collapse into one group")
    func collapsesRun() {
        let events = [
            event("typed", user: "Alex", at: 1),
            event("typed", user: "Alex", at: 2),
            event("typed", user: "Alex", at: 3),
        ]
        let groups = PadEventGrouping.group(events)
        #expect(groups.count == 1)
        #expect(groups[0].count == 3)
        // The representative is the first event; lastEvent is the most recent.
        #expect(groups[0].representative.createdAt == Date(timeIntervalSince1970: 1))
        #expect(groups[0].lastEvent.createdAt == Date(timeIntervalSince1970: 3))
    }

    @Test("a different user breaks the run")
    func breaksOnUserChange() {
        let groups = PadEventGrouping.group([
            event("typed", user: "Alex", at: 1),
            event("typed", user: "Sam", at: 2),
        ])
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.count == 1 })
    }

    @Test("a different kind breaks the run even when both kinds are collapsible")
    func breaksOnKindChange() {
        let groups = PadEventGrouping.group([
            event("typed", user: "Alex", at: 1),
            event("edited", user: "Alex", at: 2),
        ])
        #expect(groups.count == 2)
    }

    @Test("non-collapsible kinds are never merged")
    func lifecycleEventsStaySeparate() {
        // Two consecutive joins by the same user remain two distinct rows.
        let groups = PadEventGrouping.group([
            event("joined", user: "Alex", at: 1),
            event("joined", user: "Alex", at: 2),
        ])
        #expect(groups.count == 2)
    }

    @Test("a collapsible run is bracketed by lifecycle events")
    func mixedSequence() {
        let groups = PadEventGrouping.group([
            event("started", user: "Alex", at: 1),
            event("ran", user: "Alex", at: 2),
            event("ran", user: "Alex", at: 3),
            event("ended", user: "Alex", at: 4),
        ])
        // started (1) + collapsed ran×2 (1) + ended (1) = three groups.
        #expect(groups.map(\.count) == [1, 2, 1])
        #expect(groups.map { $0.representative.kind } == ["started", "ran", "ended"])
    }
}

// Serialized: OrgDirectory.load reaches a mock client and the suite asserts on
// the resulting shared lookup; keeping it serial avoids interleaving loads.
@Suite("Org directory", .serialized)
struct OrgDirectoryTests {

    @Test("display falls back to the email until a name is known")
    func displayFallsBack() {
        let directory = OrgDirectory()
        #expect(directory.name(for: "who@x.co") == nil)
        #expect(directory.display("who@x.co") == "who@x.co")
    }

    @Test("name(for:) trims whitespace and rejects blanks")
    func nameTrimsAndRejectsBlanks() {
        let directory = OrgDirectory()
        // No lookup is populated, so a blank email returns nil rather than a key hit.
        #expect(directory.name(for: "   ") == nil)
        #expect(directory.name(for: "") == nil)
    }

    @Test("loading the demo org populates names and the default language")
    func loadPopulates() async {
        let directory = OrgDirectory()
        await directory.load(for: .demo())
        #expect(directory.display("alex@demo.co") == "Alex Park")
        // Trailing whitespace is trimmed before the lookup.
        #expect(directory.name(for: " alex@demo.co ") == "Alex Park")
        #expect(directory.defaultLanguage == "go")
    }

    @Test("a failed load leaves the directory empty and unblocked for a later load")
    func failedLoadDoesNotPoisonCache() async {
        let directory = OrgDirectory()
        // The bad-key account 401s, so nothing is cached and no account is marked loaded.
        await directory.load(for: .demoBadKey())
        #expect(directory.display("alex@demo.co") == "alex@demo.co")
        #expect(directory.defaultLanguage == nil)
        // A subsequent successful load still populates rather than being skipped.
        await directory.load(for: .demo())
        #expect(directory.display("alex@demo.co") == "Alex Park")
    }
}
