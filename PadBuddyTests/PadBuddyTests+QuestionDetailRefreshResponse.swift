//
//  PadBuddyTests+QuestionDetailRefreshResponse.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Question detail refresh response")
struct QuestionDetailRefreshResponseTests {
    @Test
    func `accepts only the requested question ID`() {
        #expect(QuestionDetailRefreshResponse.matches(requestedID: 10, responseID: 10))
        #expect(!QuestionDetailRefreshResponse.matches(requestedID: 10, responseID: 11))
    }
}
