import Foundation
@testable import PadBuddy
import Testing

@Suite("Interview loader eligibility")
struct InterviewFetchEligibilityTests {
    @Test func `interactive eligibility rejects malformed overrides and missing credentials`() {
        #expect(!Account(name: "No key", apiKey: "").isInterviewFetchEligible)
        #expect(!Account(name: "Whitespace key", apiKey: " \n").isInterviewFetchEligible)
        #expect(!Account(name: "Bad URL", apiKey: "key", baseURL: "https://[").isInterviewFetchEligible)
        #expect(!Account(name: "User info", apiKey: "key", baseURL: "https://u:p@example.com").isInterviewFetchEligible)
        #expect(Account(name: "Hosted", apiKey: "key").isInterviewFetchEligible)
        let selfHosted = Account(name: "Self hosted", apiKey: "key", baseURL: "https://pads.example.com")
        #expect(selfHosted.isInterviewFetchEligible)
        #expect(Account.demo().isInterviewFetchEligible)
    }

    @Test func `directory refuses malformed server accounts without contacting the fallback host`() async {
        let account = Account(name: "Bad URL", apiKey: "key", baseURL: "https://[")
        let directory = OrgDirectory(seedFromDisk: false)
        await directory.load(for: account)
        await directory.loadMerged(for: [account])
        #expect(directory.nameByEmail.isEmpty)
        #expect(directory.defaultLanguage == nil)
    }
}
