//
//  PadBuddyTests+FavoriteQuestionEligibility.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Favorite question account eligibility (#1292)")
struct FavoriteQuestionAccountEligibilityTests {
    @Test
    func `usable credentials are offered unless the health monitor rejected them`() {
        let account = Account(name: "Production", apiKey: "secret", userEmail: "me@example.com")
        #expect(FavoriteQuestionQuery.isUsable(account: account, unauthorizedAccountIDs: []))
        #expect(!FavoriteQuestionQuery.isUsable(account: account,
                                                unauthorizedAccountIDs: [account.id]))
    }

    @Test
    func `blank keys and malformed server overrides are not offered`() {
        let blank = Account(name: "Blank", apiKey: "", userEmail: "me@example.com")
        let malformed = Account(name: "Malformed", apiKey: "secret",
                                userEmail: "me@example.com", baseURL: "not a URL")
        #expect(!FavoriteQuestionQuery.isUsable(account: blank, unauthorizedAccountIDs: []))
        #expect(!FavoriteQuestionQuery.isUsable(account: malformed, unauthorizedAccountIDs: []))
    }

    @Test
    func `the bundled demo account remains eligible`() {
        let demo = Account(name: "Demo", apiKey: "demo", isMock: true, userEmail: "demo@example.com")
        #expect(FavoriteQuestionQuery.isUsable(account: demo, unauthorizedAccountIDs: []))
    }
}
