//
//  PadBuddyTests+PadDetailResponse.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Pad detail response")
struct PadDetailResponseTests {
    @Test
    func `accepts only the requested pad ID`() {
        #expect(PadDetailResponse.matches(requestedID: "requested", responseID: "requested"))
        #expect(!PadDetailResponse.matches(requestedID: "requested", responseID: "different"))
        #expect(!PadDetailResponse.matches(requestedID: "requested", responseID: nil))
    }
}
