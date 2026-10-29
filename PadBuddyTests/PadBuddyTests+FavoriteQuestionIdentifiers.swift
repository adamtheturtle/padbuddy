import Foundation
@testable import PadBuddy
import Testing

@Suite("Favorite question identifier validation", .serialized)
struct FavoriteQuestionIdentifierTests {
    @Test(arguments: [0, -1, Int.min])
    func `live favorite mutations reject nonpositive identifiers`(_ id: Int) {
        let account = UUID()
        let store = FavoriteQuestionsStore.shared
        defer { store.remove(account: account) }
        store.add(42, title: "Valid", account: account)
        store.add(id, title: "Invalid", account: account)
        store.toggle(id, title: "Invalid", account: account)
        #expect(store.favorites(account: account) == [42])
    }
}
