//
//  coderpadTests+ScreenCredentialSavePolicy.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

@Suite("Screen credential save policy")
struct ScreenCredentialSavePolicyTests {
    @Test
    func `empty Screen credentials can be saved`() {
        #expect(permits(key: nil, validation: .idle))
        #expect(permits(key: "  ", validation: .invalid("bad")))
    }

    @Test
    func `unchanged stored credentials do not require validation`() {
        #expect(permits(key: "stored", persistedKey: "stored", validation: .idle))
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
