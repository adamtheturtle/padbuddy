import Foundation
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

@Suite("API read coalescing")
struct APIReadCoordinatorTests {
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
        await Task.yield()

        await fetch.release(0, value: 7)

        #expect(try await first.value == 7)
        #expect(try await second.value == 7)
        #expect(await fetch.count == 1)
    }
}
