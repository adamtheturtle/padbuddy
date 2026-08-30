//
//  PadBuddyTests+CompanionReloadCancellation.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Companion reload cancellation")
@MainActor
struct CompanionReloadCancellationTests {
    @Test func `invalidating reload order rejects the former current reload`() {
        var order = CompanionReloadOrder()
        let reload = order.begin()

        order.invalidate()

        #expect(!order.isCurrent(reload))
    }

    @Test func `replacing a companion reload cancels its predecessor`() async {
        let slot = CompanionReloadTaskSlot()
        let first = slot.replace {
            try? await Task.sleep(for: .seconds(60))
        }
        await Task.yield()

        let second = slot.replace {}
        await second.value

        #expect(first.isCancelled)
    }

    @Test func `cancelling the slot cancels its active reload`() async {
        let slot = CompanionReloadTaskSlot()
        let task = slot.replace {
            try? await Task.sleep(for: .seconds(60))
        }
        await Task.yield()

        slot.cancel()

        #expect(task.isCancelled)
    }
}
