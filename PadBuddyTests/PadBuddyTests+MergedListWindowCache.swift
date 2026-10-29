import Foundation
@testable import PadBuddy
import Testing

@Suite("Merged list record budgets")
@MainActor
struct MergedListWindowCacheTests {
    @Test func `duplicate account ids keep the first client and one budget slot`() {
        let cache = MergedListWindowCache<Int>(maximumRecords: 10, isCurrent: { _, _ in true })
        let id = UUID()
        let first = CoderPadClient.mock(key: "first"), duplicate = CoderPadClient.mock(key: "duplicate")
        cache.configure([(id, first.taskIdentity), (id, duplicate.taskIdentity)])
        #expect(cache.recordsPerAccount == 10)
        cache.set([1], account: id, via: duplicate, requestedLimit: 10)
        #expect(cache.retainedCount == 0)
        cache.set([2], account: id, via: first, requestedLimit: 10)
        #expect(cache.cached(id, via: first)?.values == [2])
    }

    @Test func `all account windows share one record budget`() {
        let cache = MergedListWindowCache<Int>(maximumRecords: 10, isCurrent: { _, _ in true })
        let clients = (0 ..< 3).map { CoderPadClient.mock(key: "window-\($0)") }
        let ids = clients.map { _ in UUID() }
        cache.configure(Array(zip(ids, clients)).map { (id: $0.0, identity: $0.1.taskIdentity) })
        #expect(cache.recordsPerAccount == 3)
        for (id, client) in zip(ids, clients) {
            cache.set(Array(0 ..< 100), account: id, via: client, requestedLimit: 3)
            #expect(cache.cached(id, via: client)?.values.count == 3)
            #expect(cache.cached(id, via: client)?.isComplete == false)
        }
        #expect(cache.retainedCount == 9)
    }

    @Test func `account changes trim windows and preserve incomplete coverage`() {
        let cache = MergedListWindowCache<Int>(maximumRecords: 10, isCurrent: { _, _ in true })
        let first = UUID(), second = UUID()
        let client = CoderPadClient.mock(key: "window")
        cache.configure([(first, client.taskIdentity)])
        cache.set(Array(0 ..< 8), account: first, via: client, requestedLimit: 10)
        #expect(cache.cached(first, via: client)?.isComplete == true)
        cache.configure([(first, client.taskIdentity), (second, client.taskIdentity)])
        #expect(cache.cached(first, via: client)?.values.count == 5)
        #expect(cache.cached(first, via: client)?.isComplete == false)
        cache.configure([(first, client.taskIdentity)])
        #expect(cache.cached(first, via: client, freshOnly: true) == nil)
        #expect(cache.cached(first, via: client)?.values.count == 5)
    }

    @Test func `removed and rekeyed accounts reject old callbacks`() {
        let cache = MergedListWindowCache<Int>(maximumRecords: 10, isCurrent: { _, _ in true })
        let id = UUID()
        let old = CoderPadClient.mock(key: "old"), new = CoderPadClient.mock(key: "new")
        cache.configure([(id, old.taskIdentity)])
        cache.set([1, 2], account: id, via: old, requestedLimit: 10)
        cache.configure([(id, new.taskIdentity)])
        cache.set([3], account: id, via: old, requestedLimit: 10)
        #expect(cache.cached(id, via: old) == nil)
        #expect(cache.retainedCount == 0)
        cache.set([4], account: id, via: new, requestedLimit: 10)
        cache.remove(id)
        cache.set([5], account: id, via: new, requestedLimit: 10)
        #expect(cache.retainedCount == 0)
    }

    @Test func `fresh windows expire using the monotonic clock`() {
        let cache = MergedListWindowCache<Int>(maximumRecords: 10, isCurrent: { _, _ in true })
        let id = UUID(), start = ContinuousClock.now
        let client = CoderPadClient.mock(key: "fresh")
        cache.configure([(id, client.taskIdentity)])
        cache.set([1], account: id, via: client, requestedLimit: 10, at: start)
        #expect(cache.cached(id, via: client, freshOnly: true, at: start.advanced(by: .seconds(59))) != nil)
        #expect(cache.cached(id, via: client, freshOnly: true, at: start.advanced(by: .seconds(60))) == nil)
    }

    @Test func `limited shared reads cannot inherit a larger cached list`() async throws {
        let client = CoderPadClient.mock(key: "scope-\(UUID())")
        let coordinator = APIReadCoordinator()
        let id = UUID()
        let full = try await coordinator.pads(accountID: id, client: client)
        try #require(full.count > 1)
        let limited = try await coordinator.pads(accountID: id, client: client, maximumRecords: 1)
        #expect(limited.count == 1)
        #expect(try await coordinator.pads(accountID: id, client: client).count == full.count)
    }

    @Test func `question window reads do not inherit larger cached question lists`() async throws {
        let client = CoderPadClient.mock(key: "questions-\(UUID())")
        let coordinator = APIReadCoordinator()
        let id = UUID()
        let full = try await coordinator.questions(accountID: id, client: client)
        try #require(full.count > 1)
        let limited = try await coordinator.questions(accountID: id, client: client, maximumRecords: 1)
        #expect(limited.count == 1)
        #expect(try await coordinator.questions(accountID: id, client: client).count == full.count)
    }
}
