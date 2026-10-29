import Foundation
@testable import PadBuddy
import Testing

@Suite("Directory persistence teardown")
struct DirectoryWriteTeardownTests {
    @Test func `pre-teardown save cannot recreate a removed directory`() {
        let account = UUID()
        defer { DirectoryCache.remove(account: account) }
        let beforeRemoval = DirectoryCache.writeGeneration(account: account)
        DirectoryCache.save(["old@example.com": "Old"], account: account, accepting: beforeRemoval)
        #expect(DirectoryCache.load(account: account)["old@example.com"] == "Old")

        DirectoryCache.remove(account: account)
        DirectoryCache.save(["old@example.com": "Late"], account: account, accepting: beforeRemoval)
        #expect(CacheDisk.modificationDate(kind: "directory", account: account) == nil)

        let replacement = DirectoryCache.writeGeneration(account: account)
        DirectoryCache.save(["new@example.com": "New"], account: account, accepting: replacement)
        #expect(DirectoryCache.load(account: account) == ["new@example.com": "New"])
    }
}
