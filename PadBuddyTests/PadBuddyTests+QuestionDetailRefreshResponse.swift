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

    @Test @MainActor
    func `only the newest overlapping request remains current`() {
        let state = QuestionDetailRefreshState()

        let first = state.beginRequest()
        let second = state.beginRequest()

        #expect(!state.isCurrentRequest(first))
        #expect(state.isCurrentRequest(second))
    }
}
