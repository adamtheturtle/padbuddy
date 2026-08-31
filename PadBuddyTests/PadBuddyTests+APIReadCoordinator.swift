import Foundation
import os
@testable import PadBuddy
import Testing

private actor FetchCounter {
    private(set) var value = 0
    func increment() -> Int {
        value += 1; return value
    }
}

private actor ControlledFetch {
    private var continuations: [CheckedContinuation<Int, Never>] = []
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    var count: Int {
        continuations.count
    }

    func next() async -> Int {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
            let ready = startWaiters.filter { continuations.count >= $0.count }
            startWaiters.removeAll { continuations.count >= $0.count }
            ready.forEach { $0.continuation.resume() }
        }
    }

    func waitForCount(_ count: Int) async {
        guard continuations.count < count else { return }

        await withCheckedContinuation { continuation in
            startWaiters.append((count, continuation))
        }
    }

    func release(_ index: Int, value: Int) {
        continuations[index].resume(returning: value)
    }
}

private final nonisolated class ControllableMonotonicClock: Sendable {
    private let instant = OSAllocatedUnfairLock(initialState: ContinuousClock.now)

    func now() -> ContinuousClock.Instant {
        instant.withLock { $0 }
    }

    func advance(by duration: Duration) {
        instant.withLock { $0 = $0.advanced(by: duration) }
    }
}

@Suite("API read coalescing")
struct APIReadCoordinatorTests {
    @Test func `one cancelled waiter exits without cancelling the shared fetch`() async throws {
        let coalescer = FreshRequestCoalescer<String, Int>(freshness: 60)
        let counter = FetchCounter()
        let first = Task {
            try await coalescer.value(for: "pads") {
                let value = await counter.increment()
                try await Task.sleep(for: .seconds(2))
                return value
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        let live = Task {
            try await coalescer.value(for: "pads") { await counter.increment() }
        }
        let cancellationStart = ContinuousClock.now
        first.cancel()

        do {
            _ = try await first.value
            Issue.record("The cancelled waiter should throw")
        } catch is CancellationError {}
        #expect(cancellationStart.duration(to: .now) < .milliseconds(500))
        #expect(try await live.value == 1)
        #expect(await counter.value == 1)
    }

    @Test func `late waiter cannot clear a newer task generation`() {
        var generations = FreshRequestGenerations<String>()
        generations.begin(1, for: "pads")
        generations.begin(2, for: "pads")

        let staleCompleted = generations.complete(1, for: "pads")
        #expect(!staleCompleted)
        #expect(generations.active["pads"] == 2)
        let currentCompleted = generations.complete(2, for: "pads")
        #expect(currentCompleted)
        #expect(generations.active["pads"] == nil)
    }

    @Test func `simultaneous readers share one in-flight fetch`() async throws {
        let coalescer = FreshRequestCoalescer<String, Int>(freshness: 60)
        let counter = FetchCounter()
        async let first = coalescer.value(for: "pads") {
            let value = await counter.increment()
            try await Task.sleep(for: .milliseconds(50))
            return value
        }
        async let second = coalescer.value(for: "pads") { await counter.increment() }

        #expect(try await first == 1)
        #expect(try await second == 1)
        #expect(await counter.value == 1)
    }

    @Test func `fresh values are reused and force bypasses freshness`() async throws {
        let coalescer = FreshRequestCoalescer<String, Int>(freshness: 60)
        let counter = FetchCounter()
        let first = try await coalescer.value(for: "questions") { await counter.increment() }
        let cached = try await coalescer.value(for: "questions") { await counter.increment() }
        let forced = try await coalescer.value(for: "questions", force: true) { await counter.increment() }

        #expect(first == 1)
        #expect(cached == 1)
        #expect(forced == 2)
    }

    @Test func `keys isolate accounts and endpoint identities`() async throws {
        let coalescer = FreshRequestCoalescer<String, Int>(freshness: 60)
        let counter = FetchCounter()
        _ = try await coalescer.value(for: "account-a") { await counter.increment() }
        _ = try await coalescer.value(for: "account-b") { await counter.increment() }
        #expect(await counter.value == 2)
    }

    @Test func `forced read starts after an older ordinary read and returns fresh value`() async throws {
        let coalescer = FreshRequestCoalescer<String, Int>(freshness: 60)
        let fetch = ControlledFetch()
        let ordinary = Task { try await coalescer.value(for: "pads") { await fetch.next() } }
        await fetch.waitForCount(1)
        let forced = Task { try await coalescer.value(for: "pads", force: true) { await fetch.next() } }
        await fetch.waitForCount(2)

        await fetch.release(0, value: 1)
        await fetch.release(1, value: 2)

        #expect(try await ordinary.value == 1)
        #expect(try await forced.value == 2)
        #expect(await fetch.count == 2)
    }

    @Test func `overlapping forced reads coalesce`() async throws {
        let coalescer = FreshRequestCoalescer<String, Int>(freshness: 60)
        let fetch = ControlledFetch()
        let first = Task { try await coalescer.value(for: "pads", force: true) { await fetch.next() } }
        await fetch.waitForCount(1)
        let second = Task { try await coalescer.value(for: "pads", force: true) { await fetch.next() } }
        try await Task.sleep(for: .milliseconds(20))

        await fetch.release(0, value: 7)

        #expect(try await first.value == 7)
        #expect(try await second.value == 7)
        #expect(await fetch.count == 1)
    }

    @Test func `repeated rekeying evicts the least recently used value`() async throws {
        let coalescer = FreshRequestCoalescer<String, Int>(
            freshness: 60, maximumCachedValues: 2
        )
        let counter = FetchCounter()
        _ = try await coalescer.value(for: "old-key") { await counter.increment() }
        _ = try await coalescer.value(for: "current-key") { await counter.increment() }
        _ = try await coalescer.value(for: "current-key") { await counter.increment() }
        _ = try await coalescer.value(for: "new-key") { await counter.increment() }

        let refetched = try await coalescer.value(for: "old-key") { await counter.increment() }
        #expect(refetched == 4)
        #expect(await counter.value == 4)
    }

    @Test func `freshness uses monotonic elapsed time instead of wall time`() async throws {
        let clock = ControllableMonotonicClock()
        let coalescer = FreshRequestCoalescer<String, Int>(
            freshness: 60, now: { clock.now() }
        )
        let counter = FetchCounter()
        let first = try await coalescer.value(for: "pads") { await counter.increment() }
        clock.advance(by: .seconds(59))
        let fresh = try await coalescer.value(for: "pads") { await counter.increment() }
        clock.advance(by: .seconds(2))
        let expired = try await coalescer.value(for: "pads") { await counter.increment() }

        #expect(first == 1)
        #expect(fresh == 1)
        #expect(expired == 2)
    }

    @Test func `credential teardown removes values and cancels in-flight work`() async throws {
        let coalescer = FreshRequestCoalescer<String, Int>(freshness: 60)
        let counter = FetchCounter()
        _ = try await coalescer.value(for: "retired") { await counter.increment() }
        await coalescer.remove { $0 == "retired" }
        let refetched = try await coalescer.value(for: "retired") { await counter.increment() }
        #expect(refetched == 2)

        let inFlight = Task {
            try await coalescer.value(for: "pending") {
                try await Task.sleep(for: .seconds(10))
                return 3
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        await coalescer.remove { $0 == "pending" }
        do {
            _ = try await inFlight.value
            Issue.record("Teardown should cancel matching in-flight work")
        } catch is CancellationError {}
    }

    @Test func `invalidation rejects an in-flight pre-mutation result`() async throws {
        let coalescer = FreshRequestCoalescer<String, Int>(freshness: 60)
        let fetch = ControlledFetch()
        let inFlight = Task { try await coalescer.value(for: "account") { await fetch.next() } }
        await fetch.waitForCount(1)

        await coalescer.invalidateCached { $0 == "account" }
        await fetch.release(0, value: 1)
        do {
            _ = try await inFlight.value
            Issue.record("A pre-mutation waiter must not publish its stale result")
        } catch is CancellationError {}

        // The completed read was started before the mutation, so the next
        // ordinary read must fetch again rather than serve its result.
        let counter = FetchCounter()
        let reloaded = try await coalescer.value(for: "account") { await counter.increment() + 1 }
        #expect(reloaded == 2)
    }

    @Test func `invalidation rejects every waiter sharing the stale fetch`() async throws {
        let coalescer = FreshRequestCoalescer<String, Int>(freshness: 60)
        let fetch = ControlledFetch()
        let first = Task { try await coalescer.value(for: "account") { await fetch.next() } }
        await fetch.waitForCount(1)
        let second = Task { try await coalescer.value(for: "account") { await fetch.next() } }
        try await Task.sleep(for: .milliseconds(20))

        await coalescer.invalidateCached { $0 == "account" }
        await fetch.release(0, value: 1)

        do {
            _ = try await first.value
            Issue.record("The first pre-mutation waiter must be rejected")
        } catch is CancellationError {}
        do {
            _ = try await second.value
            Issue.record("Every coalesced pre-mutation waiter must be rejected")
        } catch is CancellationError {}
        #expect(await fetch.count == 1)
    }

    @Test func `reader after invalidation starts a fresh fetch immediately`() async throws {
        let coalescer = FreshRequestCoalescer<String, Int>(freshness: 60)
        let fetch = ControlledFetch()
        let stale = Task { try await coalescer.value(for: "account") { await fetch.next() } }
        await fetch.waitForCount(1)

        await coalescer.invalidateCached { $0 == "account" }
        let fresh = Task { try await coalescer.value(for: "account") { await fetch.next() } }
        await fetch.waitForCount(2)
        await fetch.release(1, value: 2)
        #expect(try await fresh.value == 2)

        await fetch.release(0, value: 1)
        do {
            _ = try await stale.value
            Issue.record("The pre-invalidation fetch must remain fenced")
        } catch is CancellationError {}
        #expect(await fetch.count == 2)
    }

    @Test func `create update and delete invalidation force the next ordinary read`() async throws {
        let coalescer = FreshRequestCoalescer<String, Int>(freshness: 60)
        let counter = FetchCounter()

        for expectedFetch in 1 ... 4 {
            let value = try await coalescer.value(for: "account") { await counter.increment() }
            #expect(value == expectedFetch)
            if expectedFetch < 4 {
                await coalescer.remove { $0 == "account" }
            }
        }
        #expect(await counter.value == 4)
    }
}
