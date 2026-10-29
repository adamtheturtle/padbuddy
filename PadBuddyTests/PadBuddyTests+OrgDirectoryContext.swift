import Foundation
@testable import PadBuddy
import Testing

@Suite("Org directory account context", .serialized)
struct OrgDirectoryContextTests {
    @Test
    func `failed account switch replaces previous names and language with its own seed`() async {
        let directory = OrgDirectory(seedFromDisk: false)
        await directory.load(for: .demo())
        #expect(directory.defaultLanguage == "go")
        let failing = Account.demoBadKey()
        DirectoryCache.save(["next@example.com": "Next account"], account: failing.id)
        defer { DirectoryCache.remove(account: failing.id) }

        await directory.load(for: failing)

        #expect(directory.name(for: MockFixtures.demoUserEmail) == nil)
        #expect(directory.name(for: "next@example.com") == "Next account")
        #expect(directory.defaultLanguage == nil)
    }

    @Test
    func `empty merged context clears the previous organization`() async {
        let directory = OrgDirectory(seedFromDisk: false)
        await directory.load(for: .demo())
        await directory.loadMerged(for: [])
        #expect(directory.nameByEmail.isEmpty)
        #expect(directory.defaultLanguage == nil)
        // Returning to the single account must refresh rather than no-op.
        await directory.load(for: .demo())
        #expect(directory.defaultLanguage == "go")
    }
}
