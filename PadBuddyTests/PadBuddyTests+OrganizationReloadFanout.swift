//
//  PadBuddyTests+OrganizationReloadFanout.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

private actor OrganizationReloadEvents {
    private var events: [String] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func record(_ event: String) {
        events.append(event)
        let ready = waiters.filter { events.count >= $0.0 }
        waiters.removeAll { events.count >= $0.0 }
        ready.forEach { $0.1.resume() }
    }

    func waitForCount(_ count: Int) async {
        guard events.count < count else { return }

        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    var values: [String] {
        events
    }
}

@Suite("Organization reload fanout")
@MainActor
struct OrganizationReloadFanoutTests {
    @Test func `completed endpoints publish while organization remains pending`() async {
        let organizationGate = PermitGate()
        let events = OrganizationReloadEvents()

        let reload = Task { @MainActor in
            await OrganizationReloadFanout.run(
                organization: {
                    await organizationGate.wait()
                    await events.record("organization")
                },
                stats: { await events.record("stats") },
                quota: { await events.record("quota") }
            )
        }

        await events.waitForCount(2)
        #expect(await events.values.sorted() == ["quota", "stats"])

        await organizationGate.open()
        await reload.value
        #expect(await events.values.count == 3)
    }
}
