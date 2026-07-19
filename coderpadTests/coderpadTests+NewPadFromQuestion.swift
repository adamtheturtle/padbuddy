//
//  coderpadTests+NewPadFromQuestion.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

@Suite("New Pad from Question validation")
struct NewPadFromQuestionValidationTests {
    @Test func `only the freshly fetched requested question is accepted`() throws {
        let requested = try CoderPadClient.decoder.decode(
            Question.self, from: Data(#"{"id":42,"title":"Fresh"}"#.utf8)
        )
        let wrong = try CoderPadClient.decoder.decode(
            Question.self, from: Data(#"{"id":43,"title":"Wrong"}"#.utf8)
        )
        #expect(NewPadFromQuestionValidation.accept(requestedID: 42, fetched: requested)?.id == 42)
        #expect(NewPadFromQuestionValidation.accept(requestedID: 42, fetched: wrong) == nil)
    }
}
