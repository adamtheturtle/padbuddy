//
//  PadBuddyTests+NewPadValidation.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("New pad local validation")
struct NewPadValidationTests {
    @Test
    func `bounds titles`() {
        #expect(NewPadSheet.createValidationMessage(
            title: String(repeating: "a", count: 255), ownerEmail: nil
        ) == nil)
        #expect(NewPadSheet.createValidationMessage(
            title: String(repeating: "a", count: 256), ownerEmail: nil
        ) == "Title must be 255 characters or fewer.")
    }

    @Test
    func `accepts empty or well formed owners`() {
        #expect(NewPadSheet.createValidationMessage(title: nil, ownerEmail: "  ") == nil)
        #expect(NewPadSheet.createValidationMessage(
            title: nil, ownerEmail: "person+interviews@example.co.uk"
        ) == nil)
    }

    @Test(arguments: [
        "owner", "@example.com", "owner@", "owner @example.com", "owner@example", "a..b@example.com"
    ])
    func `rejects malformed owners`(_ owner: String) {
        #expect(NewPadSheet.createValidationMessage(title: nil, ownerEmail: owner)
            == "Enter a valid owner email address, or clear the Owner field.")
    }
}
