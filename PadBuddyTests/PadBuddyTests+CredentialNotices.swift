//
//  PadBuddyTests+CredentialNotices.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Credential notices")
@MainActor
struct CredentialNoticeTests {
    @Test(arguments: [AppSection.pads, .questions])
    func `merged lists show only their inline credential notice`(section: AppSection) {
        #expect(!showsNavigationCredentialBanner(isMergedView: true, section: section))
        #expect(showsNavigationCredentialBanner(isMergedView: false, section: section))
    }

    @Test(arguments: [AppSection.organization, .quota, .screen])
    func `sections without a merged list notice retain their credential banner`(section: AppSection) {
        #expect(showsNavigationCredentialBanner(isMergedView: true, section: section))
        #expect(showsNavigationCredentialBanner(isMergedView: false, section: section))
    }

    @Test func `one rejected key names its account`() {
        let account = Account(name: "Cursor", apiKey: "unused")
        #expect(rejectedAPIKeyMessage(for: [account]) == "The API key for Cursor was rejected.")
    }

    @Test func `multiple rejected keys use a count even when account names repeat`() {
        let accounts = (0 ..< 6).map { _ in Account(name: "Repeated account name", apiKey: "unused") }
        #expect(rejectedAPIKeyMessage(for: accounts) == "API keys were rejected for 6 accounts.")
    }
}
