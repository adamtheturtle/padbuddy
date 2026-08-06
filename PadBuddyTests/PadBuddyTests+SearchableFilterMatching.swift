//
//  PadBuddyTests+SearchableFilterMatching.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Foundation
import Testing

@Suite("Searchable filter matching")
struct SearchableFilterMatchingTests {
    @Test
    func `uses locale-aware case folding`() {
        let turkish = Locale(identifier: "tr_TR")

        #expect(SearchableFilterMatching.contains("İSTANBUL", query: "istanbul", locale: turkish))
        #expect(SearchableFilterMatching.contains("IĞDIR", query: "ığdır", locale: turkish))
    }

    @Test
    func `still supports partial case-insensitive matches`() {
        #expect(SearchableFilterMatching.contains("Jane Smith", query: "SMI", locale: Locale(identifier: "en")))
        #expect(!SearchableFilterMatching.contains("Jane Smith", query: "Jones", locale: Locale(identifier: "en")))
    }
}
