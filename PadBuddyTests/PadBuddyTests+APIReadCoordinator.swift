@testable import PadBuddy
import Foundation
import Testing

private actor FetchCounter {
    private(set) var value = 0
    func increment() -> Int {
        value += 1; return value
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
}
