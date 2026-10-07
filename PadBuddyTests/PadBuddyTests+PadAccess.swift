import Foundation
@testable import PadBuddy
import SwiftUI
import Testing

@Suite("Pad access and creation controls")
struct PadAccessTests {
    @Test
    func `defaults omit every new field and explicit false and empty replacement survive encoding`() throws {
        let untouched = try object(PadAccessDraft().update(padID: "DEMOXYZ2"))
        #expect(untouched.isEmpty)
        var draft = PadAccessDraft()
        draft.restricted = .disabled
        draft.coachingDisabled = .disabled
        draft.replaceEmails = true
        let update = try object(draft.update(padID: "DEMOXYZ2"))
        #expect(update == ["restrict_interviewer_access": .bool(false),
                           "disable_coaching_tips": .bool(false), "allowed_interviewer_emails": .array([])])
        draft.takeHome = .disabled
        draft.aiEnabled = .disabled
        let create = try object(draft.applying(to: PadCreate()))
        #expect(create == ["restrict_interviewer_access": .bool(false), "disable_coaching_tips": .bool(false),
                           "allowed_interviewer_emails": .array([]), "take_home": .bool(false),
                           "ai_assist_enabled": .bool(false)])
    }

    @Test
    func `emails and minutes validate without dropping invalid input`() {
        var draft = PadAccessDraft()
        draft.replaceEmails = true
        draft.emails = "Jane@EXAMPLE.COM, other@example.com\n third@example.com"
        #expect(draft.replacementEmails == ["Jane@example.com", "other@example.com", "third@example.com"])
        #expect(draft.validationMessage == nil)
        draft.emails = "not-an-email"
        #expect(draft.validationMessage != nil)
        draft.replaceEmails = false
        #expect(draft.replacementEmails == nil)
        for value in ["-1", "1.5", "2147483648", "minutes"] {
            draft.timeLimit = value
            #expect(draft.validationMessage != nil)
        }
        for value in ["0", "60", "2147483647", " "] {
            draft.timeLimit = value
            #expect(draft.validationMessage == nil)
        }
        draft.timeLimit = "60"
        draft.takeHome = .disabled
        #expect(draft.validationMessage != nil)
        draft.takeHome = .enabled
        let create = draft.applying(to: PadCreate())
        #expect(create.takeHomeTimeLimit == 60)
        #expect(create.takeHome == true)
    }

    @Test @MainActor
    func `mock saves refresh only the chosen pad and failed saves retain the draft`() async throws {
        let client = CoderPadClient.mock(key: "access-" + UUID().uuidString)
        var draft = PadAccessDraft()
        draft.restricted = .enabled
        draft.replaceEmails = true
        draft.emails = "interviewer@example.com"
        let model = PadAccessModel()
        let saved = await model.save(draft, padID: "DEMOXYZ2", client: client, isCurrent: { true })
        #expect(saved?.id == "DEMOXYZ2")
        #expect(saved?.restrictInterviewerAccess == true)
        #expect(saved?.allowedInterviewerEmails == ["interviewer@example.com"])
        #expect(model.error == nil)
        let other = try await client.getPad(id: "DEMOSWFT5")
        #expect(other.allowedInterviewerEmails != ["interviewer@example.com"])
        let failed = await model.save(draft, padID: "MISSINGPAD", client: client, isCurrent: { true })
        #expect(failed == nil)
        #expect(model.error != nil)
        #expect(model.saving == false)
        #expect(draft.emails == "interviewer@example.com")
    }

    @Test @MainActor
    func `retired account and cancelled work cannot mutate a pad`() async throws {
        let client = CoderPadClient.mock(key: "access-context-" + UUID().uuidString)
        let before = try await client.getPad(id: "DEMOXYZ2")
        var draft = PadAccessDraft()
        draft.restricted = .enabled
        let model = PadAccessModel()
        let rejected = await model.save(draft, padID: "DEMOXYZ2", client: client, isCurrent: { false })
        #expect(rejected == nil)
        #expect(model.error != nil)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await model.save(draft, padID: "DEMOXYZ2", client: client, isCurrent: { true })
        }
        let cancelled = await task.value
        #expect(cancelled == nil)
        #expect(model.error == nil)
        let after = try await client.getPad(id: "DEMOXYZ2")
        #expect(after.restrictInterviewerAccess == before.restrictInterviewerAccess)
    }

    @Test
    func `old creation drafts decode and new options round trip`() throws {
        let old = Data("""
        {"title":"Draft","language":"python3","ownerEmail":"","isPrivate":false,"executionEnabled":true}
        """.utf8)
        var draft = try JSONDecoder().decode(PadCreationDraft.self, from: old)
        #expect(draft.access == nil)
        var options = PadAccessDraft()
        options.aiEnabled = .disabled
        options.replaceEmails = true
        draft.access = options
        let restored = try JSONDecoder().decode(PadCreationDraft.self, from: JSONEncoder().encode(draft))
        #expect(restored == draft)
        #expect(PadAccessDraft().isMeaningful == false)
        #expect(options.isMeaningful == true)
    }

    @Test @MainActor
    func `access editor renders with default choices and unavailable email list`() async throws {
        let pad = try await CoderPadClient.mock().getPad(id: "DEMOXYZ2")
        let renderer = ImageRenderer(content: PadAccessEditor(
            client: .mock(), pad: pad, isCurrent: { true }, onSaved: { _ in }
        ).frame(width: 520, height: 520))
        #expect(renderer.cgImage != nil)
    }

    private func object(_ value: some Encodable) throws -> [String: JSONValue] {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode([String: JSONValue].self, from: data)
    }
}
