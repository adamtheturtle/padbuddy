//
//  PadBuddyTests+NewPadPrerequisitePolicy.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("New Pad prerequisite policy")
struct NewPadPrerequisitePolicyTests {
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
}
