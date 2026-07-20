//
//  coderpadTests+Models.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import SwiftUI
import Testing

@Suite("App navigation routes")
struct AppNavigationRouteTests {
    @Test func `new pad fallback keeps the direct-create error`() {
        let merged = AppNavigation.merged(
            pending: PadsRequest(startCreating: true, seedQuestionID: 1, createError: "Old"),
            incoming: PadsRequest(startCreating: true, seedQuestionID: 2, createError: "Unauthorized")
        )
        #expect(merged.seedQuestionID == 2)
        #expect(merged.createError == "Unauthorized")
    }

    @Test func `newer pad selection replaces its complete account generation scope`() throws {
        let oldIdentity = try ClientTaskIdentity(
            apiKey: "old", baseURL: #require(URL(string: "https://old.example"))
        )
        let newIdentity = try ClientTaskIdentity(
            apiKey: "new", baseURL: #require(URL(string: "https://new.example"))
        )
        let newAccount = UUID()

        let merged = AppNavigation.merged(
            pending: PadsRequest(
                selectPadID: "old-pad", selectPadAccountID: UUID(), selectPadClientIdentity: oldIdentity
            ),
            incoming: PadsRequest(
                selectPadID: "new-pad", selectPadAccountID: newAccount,
                selectPadClientIdentity: newIdentity
            )
        )

        #expect(merged.selectPadID == "new-pad")
        #expect(merged.selectPadAccountID == newAccount)
        #expect(merged.selectPadClientIdentity == newIdentity)
    }

    @MainActor
    @Test func `open pad publishes its id and account atomically`() {
        let accountID = UUID()
        AppNavigation.shared.openPadRequest = nil
        defer { AppNavigation.shared.openPadRequest = nil }

        AppNavigation.shared.openPad(id: "pad-1", account: accountID)
        #expect(AppNavigation.shared.openPadRequest == OpenPadNavigationRequest(id: "pad-1", accountID: accountID))
    }

    @MainActor
    @Test func `taking an open pad request clears its account scope`() {
        let accountID = UUID()
        AppNavigation.shared.openPad(id: "pad-1", account: accountID)
        #expect(AppNavigation.shared.takeOpenPadRequest()
            == OpenPadNavigationRequest(id: "pad-1", accountID: accountID))
        #expect(AppNavigation.shared.openPadRequest == nil)
        #expect(AppNavigation.shared.takeOpenPadRequest() == nil)
    }

    @Test func `new pad route keeps seed when requested account exists`() {
        let accountID = UUID()
        let route = AppNavigation.resolveNewPadRoute(
            account: accountID.uuidString,
            seedQuestionID: 42,
            availableAccountIDs: [accountID]
        )

        #expect(route.accountID == accountID)
        #expect(route.seedQuestionID == 42)
    }

    @Test func `new pad route drops seed for accountless requests`() {
        // Per-org question ids are meaningless without their owning account: a
        // stale widget/deep link seed must not apply to the current account (#1829).
        let route = AppNavigation.resolveNewPadRoute(
            account: nil,
            seedQuestionID: 42,
            availableAccountIDs: []
        )

        #expect(route.accountID == nil)
        #expect(route.seedQuestionID == nil)
    }

    @Test func `new pad route drops non-positive seeds`() {
        let accountID = UUID()
        let route = AppNavigation.resolveNewPadRoute(
            account: accountID.uuidString,
            seedQuestionID: -3,
            availableAccountIDs: [accountID]
        )

        #expect(route.accountID == accountID)
        #expect(route.seedQuestionID == nil)
    }

    @Test func `new pad route drops seed when requested account is missing`() {
        let route = AppNavigation.resolveNewPadRoute(
            account: UUID().uuidString,
            seedQuestionID: 42,
            availableAccountIDs: []
        )

        #expect(route.accountID == nil)
        #expect(route.seedQuestionID == nil)
    }
}

@Suite("App creation availability")
struct AppCreationAvailabilityTests {
    @Test func `requires a usable account and network`() {
        let live = Account(name: "Live", apiKey: "key")
        let missingKey = Account(name: "Missing", apiKey: "")
        let demo = Account.demo()

        #expect(AppCreationAvailability.canCreate(account: live, isOffline: false))
        #expect(!AppCreationAvailability.canCreate(account: missingKey, isOffline: false))
        #expect(AppCreationAvailability.canCreate(account: demo, isOffline: false))
        #expect(!AppCreationAvailability.canCreate(account: live, isOffline: true))
    }
}

#if os(macOS)
    @Suite("Menu bar create actions")
    struct MenuBarCreateActionTests {
        @Test func `my pads requires a configured account identity`() {
            let missing = Account(name: "Missing", apiKey: "key", userEmail: " \n ")
            let configured = Account(name: "Configured", apiKey: "key", userEmail: "me@example.com")

            #expect(!MenuBarView.hasConfiguredOwnershipIdentity(missing))
            #expect(MenuBarView.hasConfiguredOwnershipIdentity(configured))
        }

        @Test func `create actions require a usable source account`() {
            let live = Account(name: "Live", apiKey: "key")
            let missingKey = Account(name: "Missing", apiKey: "")
            let demo = Account.demo()

            #expect(MenuBarView.canCreatePad(account: live, isOffline: false))
            #expect(!MenuBarView.canCreatePad(account: missingKey, isOffline: false))
            #expect(MenuBarView.canCreatePad(account: demo, isOffline: false))
            #expect(!MenuBarView.canCreatePad(account: live, isOffline: true))
        }

        @Test func `create action keys are scoped by account and complete request content`() {
            let accountID = UUID()
            let account = Account(name: "Live", apiKey: "key", id: accountID)
            let otherAccount = Account(name: "Other", apiKey: "key")
            let first = PadCreate(title: "First", questionID: 42)
            let edited = PadCreate(title: "Edited", questionID: 42)
            let firstKey = MenuBarView.createPadKey(first, account: account)
            let repeatedKey = MenuBarView.createPadKey(first, account: account)

            #expect(firstKey == repeatedKey)
            #expect(firstKey != MenuBarView.createPadKey(edited, account: account))
            #expect(firstKey
                != MenuBarView.createPadKey(first, account: otherAccount))
        }
    }
#endif

@Suite("Question sort field/direction")
struct QuestionSortTests {
    private func question(
        id: Int,
        title: String = "Question",
        updatedAt: String? = nil,
        used: Int? = nil
    ) throws -> Question {
        var dict: [String: Any] = ["id": id, "title": title]
        if let updatedAt { dict["updated_at"] = updatedAt }
        if let used { dict["used"] = used }
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try CoderPadClient.decoder.decode(Question.self, from: data)
    }

    @Test func `each sort maps to the expected field`() {
        #expect(QuestionSort.lastUsedDesc.field == .lastUsed)
        #expect(QuestionSort.lastUsedAsc.field == .lastUsed)
        #expect(QuestionSort.usedDesc.field == .used)
        #expect(QuestionSort.usedAsc.field == .used)
        #expect(QuestionSort.titleAsc.field == .title)
        #expect(QuestionSort.titleDesc.field == .title)
    }

    @Test func `directions list the field's two sorts, default first`() {
        #expect(QuestionSort.directions(for: .lastUsed).map(\.sort) == [.lastUsedDesc, .lastUsedAsc])
        #expect(QuestionSort.directions(for: .used).map(\.sort) == [.usedDesc, .usedAsc])
        #expect(QuestionSort.directions(for: .title).map(\.sort) == [.titleAsc, .titleDesc])
    }

    @Test func `withField keeps the current direction slot`() {
        // Slot 0 (default) stays slot 0 across fields.
        #expect(QuestionSort.lastUsedDesc.withField(.title) == .titleAsc)
        #expect(QuestionSort.titleAsc.withField(.used) == .usedDesc)
        // Slot 1 (reverse) stays slot 1.
        #expect(QuestionSort.lastUsedAsc.withField(.title) == .titleDesc)
        #expect(QuestionSort.titleDesc.withField(.lastUsed) == .lastUsedAsc)
        // Switching to the same field is a no-op.
        #expect(QuestionSort.usedAsc.withField(.used) == .usedAsc)
    }

    @Test func `tied question sorts fall back to stable ids`() throws {
        let laterID = try question(id: 10, title: "Same", updatedAt: "2026-01-01T00:00:00Z", used: 0)
        let earlierID = try question(id: 2, title: "same", updatedAt: "2026-01-01T00:00:00Z", used: 0)

        #expect(QuestionSort.titleAsc.sorted([laterID, earlierID]).map(\.id) == [2, 10])
        #expect(QuestionSort.lastUsedDesc.sorted([laterID, earlierID]).map(\.id) == [2, 10])
        #expect(QuestionSort.usedDesc.sorted([laterID, earlierID]).map(\.id) == [2, 10])
    }
}

@Suite("Pad sort")
struct PadSortTests {
    private func pad(
        id: String,
        title: String = "Pad",
        updatedAt: String? = nil,
        createdAt: String? = nil
    ) throws -> Pad {
        var dict: [String: Any] = [
            "id": id,
            "title": title,
            "state": "started",
            "owner_email": "",
            "participants": []
        ]
        if let updatedAt { dict["updated_at"] = updatedAt }
        if let createdAt { dict["created_at"] = createdAt }
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try CoderPadClient.decoder.decode(Pad.self, from: data)
    }

    @Test func `tied pad sorts fall back to stable ids`() throws {
        let laterID = try pad(id: "B", title: "Same", updatedAt: "2026-01-01T00:00:00Z")
        let earlierID = try pad(id: "A", title: "same", updatedAt: "2026-01-01T00:00:00Z")

        #expect(PadSort.titleAsc.sorted([laterID, earlierID]).map(\.id) == ["A", "B"])
        #expect(PadSort.updatedDesc.sorted([laterID, earlierID]).map(\.id) == ["A", "B"])
    }
}

@Suite("Language helpers")
struct LanguageHelperTests {
    @Test(arguments: [
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
        ("julia", "Julia"),
        ("markdown", "Markdown"),
        ("solidity", "Solidity"),
        ("tcl", "Tcl"),
        ("verilog", "Verilog")
    ])
    func `languageDisplayName maps known codes to friendly names`(code: String, expected: String) {
        #expect(code.coderPadLanguageDisplayName == expected)
    }

    @Test(arguments: [
        ("multifile_java", "Java Project"),
        ("Multifile_java", "Java Project"),
        ("multifile_python", "Python Project"),
        ("multifile_python3", "Python 3 Project"),
        ("multifile_nodejs", "Node.js Project")
    ])
    func `languageDisplayName names multifile project environments`(code: String, expected: String) {
        #expect(code.coderPadLanguageDisplayName == expected)
    }

    @Test(arguments: [
        ("zig", "Zig"),
        ("", "")
    ])
    func `languageDisplayName capitalizes unknown codes`(code: String, expected: String) {
        #expect(code.coderPadLanguageDisplayName == expected)
    }
}

@Suite("Color hex")
struct ColorHexTests {
    @Test func `hex string round-trips through Color`() {
        let color = Color(hex: "#3478F6")
        #expect(color != nil)
        #expect(color?.hexString == "#3478F6")
    }

    @Test func `a leading hash is optional`() {
        #expect(Color(hex: "3478F6")?.hexString == "#3478F6")
    }

    @Test func `malformed hex returns nil`() {
        #expect(Color(hex: "nope") == nil)
        #expect(Color(hex: "#12345") == nil)
        #expect(Color(hex: "") == nil)
    }
}

@Suite("Quota decoder")
struct QuotaDecoderTests {
    @Test
    func `parses dates with timezone offset and fractional seconds`() throws {
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
        let quota = try CoderPadClient.decoder.decode(Quota.self, from: Data(json.utf8))
        #expect(quota.padsUsed == 57)
        #expect(quota.unlimited == true)
        #expect(quota.overagesEnabled == false)
        #expect(quota.trialExpiresAt != nil)
        #expect(quota.quotaReset != nil)
    }
}

@Suite("Pad request execution_enabled encoding")
struct PadExecutionEncodingTests {
    private func json(_ value: some Encodable) throws -> String {
        try #require(String(bytes: CoderPadClient.encoder.encode(value), encoding: .utf8))
    }

    @Test
    func `pad creation encodes execution_enabled as a JSON string, not a boolean`() throws {
        // CoderPad's pad API ignores a real boolean here and only honors the string
        // form, contrary to its published docs. See issue #305.
        let enabled = try json(PadCreate(language: "python3", executionEnabled: true))
        #expect(enabled.contains(#""execution_enabled":"true""#))
        #expect(!enabled.contains(#""execution_enabled":true"#))

        let disabled = try json(PadCreate(executionEnabled: false))
        #expect(disabled.contains(#""execution_enabled":"false""#))
    }

    @Test
    func `pad update encodes execution_enabled as a JSON string`() throws {
        let body = try json(PadUpdate(id: "ABC", executionEnabled: true))
        #expect(body.contains(#""execution_enabled":"true""#))
        #expect(!body.contains(#""execution_enabled":true"#))
    }

    @Test
    func `a nil execution flag is omitted entirely`() throws {
        #expect(try !json(PadUpdate(id: "ABC", executionEnabled: nil)).contains("execution_enabled"))
        #expect(try !json(PadCreate(language: "python3")).contains("execution_enabled"))
    }

    @Test
    func `execution_enabled decodes from either the string or the boolean shape`() throws {
        // The string form we now send.
        let stringForm = Data(#"{"id":"ABC","execution_enabled":"true"}"#.utf8)
        #expect(try JSONDecoder().decode(PadUpdate.self, from: stringForm).executionEnabled == true)
        // The boolean shape (older payloads / the published-docs shape) still decodes.
        let boolForm = Data(#"{"id":"ABC","execution_enabled":false}"#.utf8)
        #expect(try JSONDecoder().decode(PadUpdate.self, from: boolForm).executionEnabled == false)
    }
}

@Suite("List load task keys")
struct ListLoadTaskKeyTests {
    @Test
    func `single account task keys include the server endpoint`() throws {
        let first = try #require(URL(string: "https://first.example.com"))
        let second = try #require(URL(string: "https://second.example.com"))

        #expect(PadsTaskKey(apiKey: "same-key", baseURL: first, phase: .active)
            != PadsTaskKey(apiKey: "same-key", baseURL: second, phase: .active))
        #expect(QuestionsTaskKey(apiKey: "same-key", baseURL: first, phase: .active)
            != QuestionsTaskKey(apiKey: "same-key", baseURL: second, phase: .active))
    }
}
