//
//  PadBuddyTests+CompanionReloadCancellation.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Companion reload cancellation")
@MainActor
struct CompanionReloadCancellationTests {
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
}
