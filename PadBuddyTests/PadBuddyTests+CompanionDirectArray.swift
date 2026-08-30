//
//  PadBuddyTests+CompanionDirectArray.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Companion direct arrays")
struct CompanionDirectArrayTests {
    @Test func `empty direct array remains a valid empty collection`() throws {
        let items: [Int] = try usableDirectCompanionItems([], collectionName: "pads")
        #expect(items.isEmpty)
    }

    @Test func `nonempty all-malformed direct array is rejected`() {
        #expect(throws: CompanionLoadError.missingItemCollection("pads")) {
            let _: [Int] = try usableDirectCompanionItems(
                [nil, nil], collectionName: "pads"
            )
        }
    }
}
