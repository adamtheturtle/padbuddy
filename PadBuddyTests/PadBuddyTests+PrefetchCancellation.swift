import Foundation
@testable import PadBuddy
import Testing

@Suite("Prefetch cancellation health")
struct PrefetchCancellationTests {
    @Test func `cancellation does not become a new account failure`() {
        let account = UUID()
        NavigationPrefetchHealth.record(CancellationError(), account: account, kind: .pads)
        NavigationPrefetchHealth.record(URLError(.cancelled), account: account, kind: .questions)
        NavigationPrefetchHealth.record(CoderPadError.network(URLError(.cancelled)), account: account, kind: .quota)
        #expect(NavigationPrefetchHealth.snapshot(kind: .pads)[account] == nil)
        #expect(NavigationPrefetchHealth.snapshot(kind: .questions)[account] == nil)
        #expect(NavigationPrefetchHealth.snapshot(kind: .quota)[account] == nil)
    }

    @Test func `cancelling a refresh preserves a previous real failure`() {
        let account = UUID()
        defer { NavigationPrefetchHealth.clear(account: account, kind: .pads) }
        NavigationPrefetchHealth.record(URLError(.timedOut), account: account, kind: .pads)
        let failure = NavigationPrefetchHealth.snapshot(kind: .pads)[account]
        NavigationPrefetchHealth.record(CancellationError(), account: account, kind: .pads)
        #expect(NavigationPrefetchHealth.snapshot(kind: .pads)[account] == failure)
    }
}
