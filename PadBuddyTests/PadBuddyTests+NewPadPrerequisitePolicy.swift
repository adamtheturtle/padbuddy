//
//  PadBuddyTests+NewPadPrerequisitePolicy.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("New Pad prerequisite policy")
struct NewPadPrerequisitePolicyTests {
    private func question(id: Int) throws -> Question {
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "title": "Question \(id)"])
        return try CoderPadClient.decoder.decode(Question.self, from: data)
    }

    private func team(id: String, name: String) throws -> PadTeam {
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "name": name])
        return try CoderPadClient.decoder.decode(PadTeam.self, from: data)
    }

    @Test
    func `failed question load blocks only a selected question`() {
        #expect(NewPadSheet.createValidationMessage(
            title: nil, ownerEmail: nil, questionsLoadFailed: true
        ) == nil)
        #expect(NewPadSheet.createValidationMessage(
            title: nil, ownerEmail: nil, questionsLoadFailed: true, questionID: 42
        ) != nil)
    }

    @Test(arguments: ["owner@example.com", " owner@example.com "])
    func `failed organization load blocks a populated owner`(_ owner: String) {
        #expect(NewPadSheet.createValidationMessage(
            title: nil, ownerEmail: owner, organizationLoadFailed: true
        ) != nil)
    }

    @Test
    func `failed organization load blocks a selected team but permits defaults`() {
        #expect(NewPadSheet.createValidationMessage(
            title: nil, ownerEmail: "  ", organizationLoadFailed: true
        ) == nil)
        #expect(NewPadSheet.createValidationMessage(
            title: nil, ownerEmail: nil, organizationLoadFailed: true, teamID: "team-1"
        ) != nil)
    }

    @Test
    func `successful prerequisite loads permit dependent selections`() {
        #expect(NewPadSheet.createValidationMessage(
            title: "Interview", ownerEmail: "owner@example.com",
            questionID: 42, teamID: "team-1"
        ) == nil)
    }

    @Test
    func `question options are bounded while preserving a seeded question`() throws {
        let questions = try (1 ... 250).map(question(id:))
        let retained = NewPadSheet.questionsForNewPad(questions, preserving: 250, limit: 200)

        #expect(retained.count == 200)
        #expect(retained.prefix(199).map(\.id) == Array(1 ... 199))
        #expect(retained.last?.id == 250)
        #expect(NewPadSheet.questionsForNewPad(questions, preserving: nil, limit: 0).isEmpty)

        let initiallyBounded = NewPadSheet.questionsForNewPad(questions, preserving: nil, limit: 200)
        let laterSeed = NewPadSheet.questionsForNewPad(
            initiallyBounded + [questions[249]], preserving: 250, limit: 200
        )
        #expect(laterSeed.count == 200)
        #expect(laterSeed.last?.id == 250)
    }

    @Test
    func `duplicate team IDs keep one unambiguous picker option`() throws {
        let teams = try [
            team(id: "one", name: "First"),
            team(id: "one", name: "Duplicate"),
            team(id: "two", name: "Second")
        ]

        let unique = NewPadSheet.uniqueTeams(teams)

        #expect(unique.map(\.id) == ["one", "two"])
        #expect(unique.map(\.name) == ["First", "Second"])
    }

    @Test
    func `submission cancellation is not presented as a creation failure`() {
        #expect(NewPadSheet.submissionFailureMessage(for: CancellationError()) == nil)
        #expect(NewPadSheet.submissionFailureMessage(for: URLError(.badServerResponse)) != nil)
    }
}
