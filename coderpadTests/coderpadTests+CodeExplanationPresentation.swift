//
//  coderpadTests+CodeExplanationPresentation.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

@Suite("Code explanation presentation")
struct CodeExplanationPresentationTests {
    @Test
    func `loading owns presentation until result or failure`() {
        #expect(CodeExplanationPresentationState.resolve(
            hasResult: false, isExplaining: true, failed: false
        ) == .loading)
        #expect(CodeExplanationPresentationState.resolve(
            hasResult: true, isExplaining: false, failed: false
        ) == .result)
        #expect(CodeExplanationPresentationState.resolve(
            hasResult: false, isExplaining: false, failed: true
        ) == .failed)
        #expect(CodeExplanationPresentationState.resolve(
            hasResult: false, isExplaining: false, failed: false
        ) == .empty)
    }

    @Test
    func `active generation takes priority over an older result or failure`() {
        #expect(CodeExplanationPresentationState.resolve(
            hasResult: true, isExplaining: true, failed: true
        ) == .loading)
    }
}
