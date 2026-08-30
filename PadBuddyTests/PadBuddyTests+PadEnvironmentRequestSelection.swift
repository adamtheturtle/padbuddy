//
//  PadBuddyTests+PadEnvironmentRequestSelection.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Pad environment request selection")
struct PadEnvironmentRequestSelectionTests {
    @Test
    func `filters invalid duplicates while preserving order`() {
        let selection = PadEnvironmentRequestSelection.select(from: [0, 3, -1, 3, 2])

        #expect(selection.ids == [3, 2])
        #expect(!selection.wasTruncated)
    }

    @Test
    func `caps unique environment IDs and reports truncation`() {
        let source = Array(1 ... PadEnvironmentRequestSelection.limit + 1)

        let selection = PadEnvironmentRequestSelection.select(from: source)

        #expect(selection.ids == Array(1 ... PadEnvironmentRequestSelection.limit))
        #expect(selection.wasTruncated)
    }

    @Test
    func `accepts only a response with the requested environment ID`() {
        #expect(PadEnvironmentResponse.matches(requestedID: 10, responseID: 10))
        #expect(!PadEnvironmentResponse.matches(requestedID: 10, responseID: 11))
        #expect(!PadEnvironmentResponse.matches(requestedID: 10, responseID: nil))
    }
}
