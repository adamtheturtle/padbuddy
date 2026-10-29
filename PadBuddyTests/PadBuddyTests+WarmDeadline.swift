import Foundation
@testable import PadBuddy
import Testing

private actor UncooperativeWarm {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false

    func run() async {
        started = true
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@Suite("Navigation warm hard deadline")
@MainActor
struct WarmDeadlineTests {
    @Test func `deadline returns without waiting for an uncooperative body and keeps its permit`() async {
        let slots = NavigationWarmSlots(maximum: 1)
        let held = UncooperativeWarm()
        await NavigationSessionLoader.withWarmBudget(.milliseconds(10), slots: slots) {
            await held.run()
        }
        #expect(await held.started)

        var replacementRan = false
        await NavigationSessionLoader.withWarmBudget(.seconds(1), slots: slots) {
            replacementRan = true
        }
        #expect(!replacementRan)
        await held.release()
    }
}
