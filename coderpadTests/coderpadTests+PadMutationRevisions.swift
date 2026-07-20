//
//  coderpadTests+PadMutationRevisions.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Pad mutation ordering (#1332)")
struct PadMutationRevisionTests {
    @Test
    func `deletion invalidates an older end refresh without crossing scopes`() throws {
        var revisions = PadMutationRevisionStore()
        let account = UUID()
        let otherAccount = UUID()
        let client = try ClientTaskIdentity(
            apiKey: "key", baseURL: #require(URL(string: "https://example.com"))
        )
        let key = PadMutationRevisionStore.Key(accountID: account, padID: "pad", clientIdentity: client)
        let other = PadMutationRevisionStore.Key(accountID: otherAccount, padID: "pad", clientIdentity: client)
        let endRefresh = revisions.claim(key)
        let unrelated = revisions.claim(other)

        revisions.invalidate(key)
        let later = revisions.claim(key)

        #expect(!revisions.isCurrent(endRefresh))
        #expect(revisions.isCurrent(unrelated))
        #expect(revisions.isCurrent(later))
    }
}
