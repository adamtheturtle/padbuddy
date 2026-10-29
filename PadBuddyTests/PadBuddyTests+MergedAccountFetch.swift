import Foundation
@testable import PadBuddy
import Testing

private actor MergedFetchProbe {
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private var active = 0
    private(set) var started = 0
    private(set) var peak = 0

    func fetch(_ value: Int) async -> Int {
        started += 1
        active += 1
        peak = max(peak, active)
        if started >= MergedAccountFetch.maximumConcurrent {
            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()
        }
        if !released {
            await withCheckedContinuation { pending.append($0) }
        }
        active -= 1
        return value
    }

    func waitForInitialLoads() async {
        guard started < MergedAccountFetch.maximumConcurrent else { return }

        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseAll() {
        released = true
        pending.forEach { $0.resume() }
        pending.removeAll()
    }
}

@Suite("Bounded merged account fetching")
@MainActor
struct MergedAccountFetchTests {
    @Test func `refills without exceeding the shared concurrency budget`() async {
        let probe = MergedFetchProbe()
        let work = Task {
            await MergedAccountFetch.results(
                for: Array(0 ..< 20), shouldContinue: { true }, fetch: { await probe.fetch($0) }
            )
        }
        await probe.waitForInitialLoads()
        #expect(await probe.started == MergedAccountFetch.maximumConcurrent)
        await probe.releaseAll()
        #expect(await work.value.sorted() == Array(0 ..< 20))
        #expect(await probe.peak <= MergedAccountFetch.maximumConcurrent)
    }

    @Test func `a changed session stops refilling the task group`() async {
        let probe = MergedFetchProbe()
        var current = true
        let work = Task {
            await MergedAccountFetch.results(
                for: Array(0 ..< 20), shouldContinue: { current }, fetch: { await probe.fetch($0) }
            )
        }
        await probe.waitForInitialLoads()
        current = false
        await probe.releaseAll()
        #expect(await work.value.isEmpty)
        #expect(await probe.started == MergedAccountFetch.maximumConcurrent)
    }

    @Test func `account targets are eligible and unique before client creation`() {
        let account = Account(name: "A", apiKey: "key")
        let invalid = Account(name: "Bad URL", apiKey: "key", baseURL: "https://[")
        #expect(MergedAccountFetch.eligibleAccounts([account, account, invalid]).map(\.id) == [account.id])
    }
}
