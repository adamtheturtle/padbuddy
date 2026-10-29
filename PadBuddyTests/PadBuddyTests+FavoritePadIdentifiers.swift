import Foundation
@testable import PadBuddy
import Testing

@Suite("Favorite pad identifier validation", .serialized)
struct FavoritePadIdentifierTests {
    @Test(arguments: ["", " \n", "../pad", "abc/def", "abc\nx", String(repeating: "a", count: 65)])
    func `invalid pad identifiers cannot enter favorites through live mutations`(_ id: String) {
        let account = UUID()
        let store = FavoritePadsStore.shared
        defer { store.remove(account: account) }
        store.add(id, title: "Invalid", account: account)
        store.toggle(id, title: "Invalid", account: account)
        #expect(store.favorites(account: account).isEmpty)
    }

    @Test func `restoration normalizes valid identifiers before deduplication and rejects invalid ones`() {
        let entries = FavoritePadsStore.sanitized([
            FavoritePad(id: "  abc-123_\n", title: "First", addedAt: nil),
            FavoritePad(id: "abc-123_", title: "Duplicate", addedAt: nil),
            FavoritePad(id: "../invalid", title: "Invalid", addedAt: nil)
        ])
        #expect(entries.map(\.id) == ["abc-123_"])
        #expect(entries.first?.title == "First")
        #expect(FavoritePadsStore.normalizedPadID(String(repeating: " ", count: 1_000_000)) == nil)
    }
}
