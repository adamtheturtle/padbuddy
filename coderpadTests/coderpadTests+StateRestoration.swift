//
//  coderpadTests+StateRestoration.swift
//  coderpadTests
//
//  Unit coverage for the launch-time selection-restore decision (#273): which saved
//  pad/question, if any, should be reselected once the list has loaded. The decision
//  is a pure function so it's testable without standing up a SwiftUI view.
//

@testable import CoderPad
import Testing

@MainActor
struct SelectionRestoreTests {
    @Test func `restores the saved pad when nothing blocks it`() {
        let target = PadsView.padToRestore(
            savedID: "p2", hasSelection: false, hasPendingOpen: false,
            availableIDs: ["p1", "p2", "p3"]
        )
        #expect(target == "p2")
    }

    @Test func `does not restore a pad when one is already selected`() {
        let target = PadsView.padToRestore(
            savedID: "p2", hasSelection: true, hasPendingOpen: false,
            availableIDs: ["p1", "p2"]
        )
        #expect(target == nil)
    }

    @Test func `does not restore a pad while a deep link is pending`() {
        let target = PadsView.padToRestore(
            savedID: "p2", hasSelection: false, hasPendingOpen: true,
            availableIDs: ["p1", "p2"]
        )
        #expect(target == nil)
    }

    @Test func `does not restore a pad missing from the loaded list`() {
        let target = PadsView.padToRestore(
            savedID: "gone", hasSelection: false, hasPendingOpen: false,
            availableIDs: ["p1", "p2"]
        )
        #expect(target == nil)
    }

    @Test func `does not restore a pad when nothing was saved`() {
        let target = PadsView.padToRestore(
            savedID: nil, hasSelection: false, hasPendingOpen: false,
            availableIDs: ["p1", "p2"]
        )
        #expect(target == nil)
    }

    @Test func `restores the saved question when nothing blocks it`() {
        let target = QuestionsView.questionToRestore(
            savedID: 42, hasSelection: false, hasPendingNavigation: false,
            availableIDs: [7, 42, 99]
        )
        #expect(target == 42)
    }

    @Test func `does not restore a question while a navigation is pending`() {
        let target = QuestionsView.questionToRestore(
            savedID: 42, hasSelection: false, hasPendingNavigation: true,
            availableIDs: [7, 42]
        )
        #expect(target == nil)
    }

    @Test func `does not restore a question missing from the loaded list`() {
        let target = QuestionsView.questionToRestore(
            savedID: 1234, hasSelection: false, hasPendingNavigation: false,
            availableIDs: [7, 42]
        )
        #expect(target == nil)
    }
}
