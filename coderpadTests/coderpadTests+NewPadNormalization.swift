//
//  coderpadTests+NewPadNormalization.swift
//  coderpadTests
//
//  Split from coderpadTests+Models.swift to keep both files under the
//  file-length limit.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("New pad request normalization")
struct NewPadRequestNormalizationTests {
    @Test
    func `create body trims optional title and owner fields`() {
        let body = NewPadSheet.normalizedCreateBody(NewPadSheet.CreateDraft(
            title: "  Onsite: Jane  \n",
            language: "python3",
            ownerEmail: "\towner@example.com  ",
            contents: nil,
            notes: nil,
            isPrivate: true,
            executionEnabled: false,
            questionID: 42,
            teamID: "team-1"
        ))

        #expect(body.title == "Onsite: Jane")
        #expect(body.ownerEmail == "owner@example.com")
        #expect(body.language == "python3")
        #expect(body.isPrivate == true)
        #expect(body.executionEnabled == false)
        #expect(body.questionID == 42)
        #expect(body.teamID == "team-1")
    }

    @Test
    func `create body omits whitespace only title and owner fields`() {
        let body = NewPadSheet.normalizedCreateBody(NewPadSheet.CreateDraft(
            title: " \n ",
            language: "python3",
            ownerEmail: "\t",
            contents: nil,
            notes: nil,
            isPrivate: false,
            executionEnabled: true,
            questionID: nil,
            teamID: nil
        ))

        #expect(body.title == nil)
        #expect(body.ownerEmail == nil)
    }

    @Test
    func `create body folds interior control characters in title and owner`() {
        let body = NewPadSheet.normalizedCreateBody(NewPadSheet.CreateDraft(
            title: "Onsite:\nJane\tDoe",
            language: "python3",
            ownerEmail: "owner@\u{0}example.com",
            contents: nil,
            notes: nil,
            isPrivate: nil,
            executionEnabled: nil,
            questionID: nil,
            teamID: nil
        ))

        // Folded to a space rather than deleted, so the words either side of the
        // break stay apart instead of running together (#2639).
        #expect(body.title == "Onsite: Jane Doe")
        #expect(body.ownerEmail == "owner@ example.com")
    }

    @Test
    func `create body drops a language the pad API cannot create`() {
        func language(_ value: String?) -> String? {
            NewPadSheet.normalizedCreateBody(NewPadSheet.CreateDraft(
                title: nil,
                language: value,
                ownerEmail: nil,
                contents: nil,
                notes: nil,
                isPrivate: nil,
                executionEnabled: nil,
                questionID: nil,
                teamID: nil
            )).language
        }

        // Project environments and unknown codes are rejected by the create API, so
        // they're dropped and the account default applies instead (#2638).
        #expect(language("react") == nil)
        #expect(language("not-a-language") == nil)
        #expect(language("  ") == nil)
        #expect(language(nil) == nil)
        // A supported code survives, canonicalized to the form the gate matched.
        #expect(language("python3") == "python3")
        #expect(language("  Python3 ") == "python3")
    }
}
