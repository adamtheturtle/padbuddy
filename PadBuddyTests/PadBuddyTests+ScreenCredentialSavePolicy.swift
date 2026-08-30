//
//  PadBuddyTests+ScreenCredentialSavePolicy.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Screen credential save policy")
struct ScreenCredentialSavePolicyTests {
    @Test
    func `empty Screen credentials can be saved`() {
        #expect(permits(key: nil, validation: .idle))
        #expect(permits(key: "  ", validation: .invalid("bad")))
        #expect(permits(key: "\n\r\t", validation: .invalid("bad")))
    }

    @Test
    func `credential normalization treats line breaks as empty`() {
        #expect(AccountEditor.normalizedCredential(" \n\r\t ").isEmpty)
        #expect(AccountEditor.normalizedCredential(" \nkey\r ") == "key")
    }

    @Test
    func `unchanged stored credentials do not require validation`() {
        #expect(permits(key: "stored", validation: .idle, persistedKey: "stored"))
    }

    @Test
    func `changed credentials require successful validation`() {
        #expect(!permits(key: "new", validation: .idle))
        #expect(!permits(key: "new", validation: .validating))
        #expect(!permits(key: "new", validation: .invalid("Rejected")))
        #expect(permits(key: "new", validation: .valid))
    }

    @Test
    func `a region change also requires validation`() {
        #expect(!permits(key: "stored", validation: .idle, region: .europe,
                         persistedKey: "stored", persistedRegion: .unitedStates))
    }

    private func permits(
        key: String?, validation: ValidationState,
        region: ScreenRegion = .unitedStates, persistedKey: String? = nil,
        persistedRegion: ScreenRegion = .unitedStates
    ) -> Bool {
        AccountEditor.ScreenCredentialSavePolicy.permits(
            key: key, region: region, persistedKey: persistedKey,
            persistedRegion: persistedRegion, validation: validation
        )
    }
}
