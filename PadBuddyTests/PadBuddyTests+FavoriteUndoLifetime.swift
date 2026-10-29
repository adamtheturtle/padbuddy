import Foundation
@testable import PadBuddy
import Testing

@Suite("Favorite undo account lifetime", .serialized)
struct FavoriteUndoLifetimeTests {
    @Test func `account removal prevents pad favorite undo from restoring private state`() {
        let account = UUID()
        let store = FavoritePadsStore.shared
        defer { store.remove(account: account) }
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.add("abc123", title: "Interview", account: account)
        undo.beginUndoGrouping()
        store.remove("abc123", account: account, undoManager: undo)
        undo.endUndoGrouping()
        store.remove(account: account)
        undo.undo()
        #expect(store.favorites(account: account).isEmpty)
    }

    @Test func `account removal prevents question favorite undo from restoring private state`() {
        let account = UUID()
        let store = FavoriteQuestionsStore.shared
        defer { store.remove(account: account) }
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.add(42, title: "Question", account: account)
        undo.beginUndoGrouping()
        store.remove(42, account: account, undoManager: undo)
        undo.endUndoGrouping()
        store.remove(account: account)
        undo.undo()
        #expect(store.favorites(account: account).isEmpty)
    }

    @Test func `undo remains available during the same account lifetime`() {
        let account = UUID()
        let store = FavoritePadsStore.shared
        defer { store.remove(account: account) }
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.add("abc123", title: "Interview", account: account)
        undo.beginUndoGrouping()
        store.remove("abc123", account: account, undoManager: undo)
        undo.endUndoGrouping()
        undo.undo()
        #expect(store.favorites(account: account) == ["abc123"])
    }

    @Test func `account order undo cannot restore a removed account's references`() {
        let account = UUID()
        let store = FavoritesOrderStore.shared
        defer { store.remove(account: account) }
        let present: [FavoriteRef] = [.pad("abc123"), .pad("def456")]
        store.moveToEnd(.pad("abc123"), present: present, account: account)
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        store.moveToEnd(.pad("def456"), present: present, account: account, undoManager: undo)
        undo.endUndoGrouping()
        store.remove(account: account)
        undo.undo()
        #expect(store.snapshot(account: account).account.isEmpty)
    }

    @Test func `reusing an account UUID cannot revive an older undo lifetime`() {
        let account = UUID()
        defer { AccountUndoLifetime.invalidate(account) }
        let old = AccountUndoLifetime.capture([account])
        AccountUndoLifetime.invalidate(account)
        let replacement = AccountUndoLifetime.capture([account])
        #expect(!old.isCurrent)
        #expect(replacement.isCurrent)
    }
}
