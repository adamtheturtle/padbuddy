@testable import PadBuddy
import Foundation
import Testing

@Suite("Companion platform policy")
struct CompanionPlatformPolicyTests {
    @Test func `companion section labels resolve through localization`() {
        #expect(companionSectionDisplayName("pads") == String(localized: "Pads"))
        #expect(companionSectionDisplayName("QUESTIONS") == String(localized: "Questions"))
    }

    @Test(arguments: [
        CompanionPlatformPolicy.Platform.watchOS,
        CompanionPlatformPolicy.Platform.tvOS
    ])
    func `companion platforms are read-only`(_ platform: CompanionPlatformPolicy.Platform) {
        let policy = CompanionPlatformPolicy.policy(for: platform)
        #expect(policy.browsableSections == ["pads", "questions"])
        #expect(!policy.allowsMutations)
        #expect(!policy.allowsSettings)
    }
}
