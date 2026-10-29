import AppGroupMailbox
import Foundation
@testable import PadBuddy
import Testing

@Suite("Durable bounded deletion cleanup")
struct DeletionOutboxTests {
    @Test func `a stalled consumer retains more than the UI buffer and deduplicates retries`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let outbox = try DeletionOutbox(root: root)
        let identity = ClientTaskIdentity(apiKey: "private-test-key", baseURL: .staticURL("https://example.test"))
        let owner = UUID()
        for index in 1 ... 200 {
            let work = DeletionWork(kind: .question, recordID: String(index), account: owner, identity: identity)
            try outbox.enqueue(work)
            try outbox.enqueue(work)
        }
        // Reopening models a terminated producer, before any cleanup was consumed.
        let recovered = try DeletionOutbox(root: root)
        var ids = Set<String>()
        while let claim = try recovered.mailbox.claimPending(limit: 1).first {
            #expect(ids.insert(claim.message.recordID).inserted)
            try claim.acknowledge()
        }
        #expect(ids.count == 200)
    }

    @Test func `capacity rejects new work without discarding pending cleanup`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let outbox = try DeletionOutbox(root: root, capacity: 1)
        let identity = ClientTaskIdentity(apiKey: "key", baseURL: .staticURL("https://example.test"))
        let first = DeletionWork(kind: .pad, recordID: "first", account: UUID(), identity: identity)
        try outbox.enqueue(first)
        #expect(throws: AppGroupMailbox<DeletionWork>.MailboxError.mailboxFull) {
            try outbox.enqueue(DeletionWork(kind: .pad, recordID: "second", account: first.account, identity: identity))
        }
        let claim = try #require(outbox.mailbox.claimPending(limit: 1).first)
        #expect(claim.message.recordID == "first")
        try claim.release()
        #expect(try outbox.mailbox.claimPending(limit: 1).first?.message.recordID == "first")
    }

    @Test func `persisted identity excludes API keys and distinguishes credentials and account`() throws {
        let identity = ClientTaskIdentity(apiKey: "secret-key-that-must-not-be-persisted",
                                          baseURL: .staticURL("https://example.test"))
        let owner = UUID()
        let work = DeletionWork(kind: .pad, recordID: "pad", account: owner, identity: identity)
        let encoded = try JSONEncoder().encode(work)
        let text = try #require(String(data: encoded, encoding: .utf8))
        #expect(!text.contains(identity.apiKey))
        let rekeyed = ClientTaskIdentity(apiKey: "new-key", baseURL: identity.baseURL)
        #expect(work.clientFingerprint != DeletionWork.fingerprint(rekeyed))
        let other = DeletionWork(kind: .pad, recordID: "pad", account: UUID(), identity: identity)
        #expect(work.stableID != other.stableID)
    }
}
